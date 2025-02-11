import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineString} from "firebase-functions/params";
import * as admin from "firebase-admin";
import axios from "axios";

// Config
const finnhubApiKey = defineString("FINNHUB_API_KEY");

// Type definitions
interface FinnhubNewsResponse {
  category: string;
  datetime: number;
  headline: string;
  id: number;
  image: string;
  related: string;
  source: string;
  summary: string;
  url: string;
}

interface NewsItem {
  id: number;
  headline: string;
  summary: string;
  url: string;
  imageUrl: string;
  source: string;
  category: string;
  categories: string[];
  publishedAt: admin.firestore.Timestamp;
}

/**
 * Maps Finnhub categories to our internal categories.
 * @param {string} category - The Finnhub category.
 * @param {string} headline - The Finnhub headline.
 * @param {string} source - The Finnhub source.
 * @return {string} Our internal category.
 */
function getFinnhubCategory(category: string, headline = "", source = ""): string {
  const categoryMap: Record<string, string> = {
    "top news": "stocks",
    "business": "stocks",
    "company news": "stocks",
    "crypto": "crypto",
    "cryptocurrency": "crypto",
    "forex": "stocks",
    "merger": "stocks",
    "general": "stocks",
  };

  // Convert all text to lowercase for case-insensitive matching
  const lowercasedCategory = category.toLowerCase();
  const lowercasedHeadline = headline.toLowerCase();
  const lowercasedSource = source.toLowerCase();

  // Crypto news sources
  const cryptoSources = [
    "coindesk",
    "cointelegraph",
    "cryptonews",
    "bitcoin.com",
    "decrypt",
    "theblock",
    "coinbase",
    "binance",
    "cryptoslate",
  ];

  // Crypto-related keywords
  const cryptoKeywords = [
    "crypto",
    "bitcoin",
    "btc",
    "ethereum",
    "eth",
    "blockchain",
    "defi",
    "nft",
    "web3",
    "altcoin",
    "cryptocurrency",
    "binance",
    "coinbase",
    "token",
    "mining",
    "staking",
    "dao",
    "dex",
    "wallet",
  ];

  // Check if the source is a crypto news source
  if (cryptoSources.some((src) => lowercasedSource.includes(src))) {
    return "crypto";
  }

  // Check if the headline contains crypto-related keywords
  if (cryptoKeywords.some((keyword) => lowercasedHeadline.includes(keyword))) {
    return "crypto";
  }

  // Check if the category contains crypto-related keywords
  if (cryptoKeywords.some((keyword) => lowercasedCategory.includes(keyword))) {
    return "crypto";
  }

  return categoryMap[lowercasedCategory] || "stocks";
}

/**
 * Syncs news every 5 minutes from Finnhub API.
 */
export const syncNews = onSchedule(
  {
    schedule: "*/5 * * * *",
    memory: "256MiB",
    timeZone: "UTC",
    retryCount: 3,
    maxInstances: 1,
    labels: {
      job: "news-sync",
    },
  },
  async () => {
    try {
      console.log("🔄 Starting news sync at:", new Date().toISOString());
      const now = admin.firestore.Timestamp.now();
      const oneDayAgo = admin.firestore.Timestamp.fromDate(
        new Date(now.toMillis() - 24 * 60 * 60 * 1000),
      );

      // Categories to fetch
      const categories = ["crypto", "general", "forex", "merger", "business"];
      const allArticles: FinnhubNewsResponse[] = [];

      // Fetch news for each category
      for (const category of categories) {
        console.log(`📡 Fetching ${category} news...`);
        try {
          const response = await axios.get(
            "https://finnhub.io/api/v1/news",
            {
              params: {
                token: finnhubApiKey.value(),
                category: category,
                minId: 0,
              },
            }
          );

          if (response.data && Array.isArray(response.data)) {
            // For crypto news, make sure we properly categorize them
            const articles = response.data.map((article: FinnhubNewsResponse) => {
              if (category === "crypto") {
                return {
                  ...article,
                  category: "crypto", // Force category to crypto for these articles
                };
              }
              return article;
            });

            console.log(`✅ Fetched ${articles.length} ${category} articles`);
            allArticles.push(...articles);
          }
        } catch (error) {
          console.error(`❌ Error fetching ${category} news:`, error);
        }
      }

      console.log(`📊 Total articles fetched: ${allArticles.length}`);

      // Process articles
      const batch = admin.firestore().batch();
      const processedArticles: NewsItem[] = [];
      const processedIds = new Set<number>();

      for (const article of allArticles) {
        try {
          // Skip duplicates
          if (processedIds.has(article.id)) {
            console.log(`⏩ Skipping duplicate article ${article.id}`);
            continue;
          }

          // Validate required fields
          if (!article.headline?.trim() || article.headline.trim().length === 0) {
            console.log(`⚠️ Skipping article ${article.id} - Missing headline`);
            continue;
          }

          if (!article.datetime) {
            console.log(`⚠️ Skipping article ${article.id} - Missing timestamp`);
            continue;
          }

          const publishedAt = admin.firestore.Timestamp.fromMillis(
            article.datetime * 1000,
          );

          // Only process articles from last 24 hours
          if (publishedAt.toMillis() < oneDayAgo.toMillis()) {
            console.log(`⏩ Skipping old article ${article.id} from ${publishedAt.toDate()}`);
            continue;
          }

          // Validate and clean other fields
          const summary = article.summary?.trim() || article.headline.trim();
          const source = article.source?.trim() || "Unknown";
          const imageUrl = article.image?.trim() || "";
          const category = getFinnhubCategory(
            article.category || "general",
            article.headline || "",
            article.source || ""
          );

          processedIds.add(article.id);

          const newsItem: NewsItem = {
            id: article.id,
            headline: article.headline.trim(),
            summary: summary,
            url: article.url?.trim() || "",
            imageUrl: imageUrl,
            source: source,
            category: category,
            categories: [category],
            publishedAt,
          };

          const ref = admin.firestore()
            .collection("news")
            .doc(newsItem.id.toString());
          batch.set(ref, newsItem, {merge: true});
          processedArticles.push(newsItem);

          console.log(`✅ Processed article ${newsItem.id}: ${newsItem.headline}`);
        } catch (error) {
          console.error(`❌ Error processing article ${article.id}:`, error);
          continue;
        }
      }

      if (processedArticles.length > 0) {
        await batch.commit();
        console.log(`✅ Saved ${processedArticles.length} articles`);

        // Group articles by category for logging
        const categoryCount = processedArticles.reduce((acc, article) => {
          acc[article.category] = (acc[article.category] || 0) + 1;
          return acc;
        }, {} as Record<string, number>);

        console.log("📊 Articles by category:");
        Object.entries(categoryCount).forEach(([category, count]) => {
          console.log(`  ${category}: ${count} articles`);
        });
      }

      // Clean up old news (older than 24 hours)
      const oldNews = await admin.firestore()
        .collection("news")
        .where("publishedAt", "<", oneDayAgo)
        .get();

      if (!oldNews.empty) {
        const cleanupBatch = admin.firestore().batch();
        oldNews.docs.forEach((doc) => {
          cleanupBatch.delete(doc.ref);
        });
        await cleanupBatch.commit();
        console.log(`🧹 Cleaned up ${oldNews.size} old articles`);
      }

      // Update sync status in Firestore
      await admin.firestore()
        .collection("system")
        .doc("newsSync")
        .set({
          lastSync: now,
          lastArticleId: allArticles[0]?.id || 0,
          newArticles: processedArticles.length,
          syncStatus: "success",
        }, {merge: true});

      console.log("✅ News sync completed successfully");
    } catch (error) {
      console.error("❌ Error syncing news:", error);
      // Update sync status on error
      await admin.firestore()
        .collection("system")
        .doc("newsSync")
        .set({
          lastSync: admin.firestore.Timestamp.now(),
          syncStatus: "error",
          error: error instanceof Error ? error.message : String(error),
        }, {merge: true});
    }
  },
);

