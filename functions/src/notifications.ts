import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import axios from "axios";

// Type definitions
interface User {
  fcmToken?: string;
  notificationsEnabled?: boolean;
  email?: string;
  lastLoginAt?: admin.firestore.Timestamp;
}

interface UserSession {
  userId: string;
  deviceInfo: string;
  platform: string;
  createdAt: admin.firestore.Timestamp;
  isNewUser: boolean;
  fcmToken: string;
}

interface Asset {
  symbol: string;
  name: string;
  currentPrice: number;
  lastPrice: number;
  lastUpdated: admin.firestore.Timestamp;
}

interface PortfolioAsset {
  symbol: string;
  name: string;
  quantity: number;
  averagePrice: number;
}

/**
 * Sends a push notification to a specific device token.
 * @param {string} token - The FCM token to send the notification to.
 * @param {Object} notification - The notification payload.
 */
async function sendPushNotification(
  token: string,
  notification: {
    title: string;
    body: string;
    data?: Record<string, string>;
  },
) {
  try {
    console.log("🔄 Attempting to send push notification:", {
      token: token.substring(0, 10) + "...",
      title: notification.title,
      body: notification.body,
      data: notification.data,
    });

    const message = {
      token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data,
      android: {
        priority: "high" as const,
        notification: {
          sound: "default",
          priority: "high" as const,
          channelId: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            sound: "default",
            badge: 1,
            mutableContent: true,
            priority: 10,
          },
        },
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
      },
    };

    await admin.messaging().send(message);
    console.log("✅ Push notification sent successfully");
  } catch (error: unknown) {
    console.error("❌ Error sending push notification:", error);

    // Check if token is invalid
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (errorMessage.includes("registration-token-not-registered")) {
      console.log("🔄 Token is invalid, removing from user document...");
      // Find and update user document with this token
      try {
        const usersSnapshot = await admin.firestore()
          .collection("users")
          .where("fcmToken", "==", token)
          .get();

        if (!usersSnapshot.empty) {
          const batch = admin.firestore().batch();
          usersSnapshot.docs.forEach((doc) => {
            console.log("📱 Removing invalid token for user:", doc.id);
            batch.update(doc.ref, {
              fcmToken: admin.firestore.FieldValue.delete(),
              notificationsEnabled: false,
              lastTokenError: errorMessage,
              lastTokenErrorAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          });
          await batch.commit();
          console.log("✅ Removed invalid token from user document(s)");
        } else {
          console.log("⚠️ No user found with the invalid token");
        }
      } catch (dbError) {
        console.error("❌ Error updating user document:", dbError);
      }
    }
  }
}

/**
 * Sends a welcome notification when a new user document is created.
 */
export const onNewUserWelcome = onDocumentCreated(
  "userSessions/{sessionId}",
  async (event) => {
    const session = event.data?.data() as UserSession | undefined;
    if (!session?.userId || !session.isNewUser || !session.fcmToken) {
      console.log("⏩ Skipping welcome notification - Not a new user or missing data");
      return;
    }

    try {
      const notification = {
        title: "Welcome to FinTrack! 👋",
        body: "Start tracking your investments and stay updated with market news.",
        data: {
          type: "WELCOME",
          action: "OPEN_ONBOARDING",
          userId: session.userId,
        },
      };
      await sendPushNotification(session.fcmToken, notification);
      console.log("✅ Welcome notification sent to new user:", session.userId);
    } catch (error) {
      console.error("❌ Error sending welcome notification:", error);
    }
  },
);

/**
 * Sends a welcome back notification when user signs in.
 */
export const onUserSession = onDocumentCreated(
  "userSessions/{sessionId}",
  async (event) => {
    const session = event.data?.data() as UserSession | undefined;
    if (!session?.userId || session.isNewUser || !session.fcmToken) {
      console.log("⏩ Skipping welcome back notification - New user or missing data");
      return;
    }

    try {
      const notification = {
        title: "Welcome Back! 👋",
        body: "Check out the latest market updates since your last visit.",
        data: {
          type: "WELCOME_BACK",
          action: "OPEN_PORTFOLIO",
          userId: session.userId,
          sessionId: event.params.sessionId,
        },
      };
      await sendPushNotification(session.fcmToken, notification);
      console.log("✅ Welcome back notification sent to user:", session.userId);
    } catch (error) {
      console.error("❌ Error sending welcome back notification:", error);
    }
  },
);

/**
 * Sends news digest every 8 hours.
 */
export const sendNewsNotifications = onSchedule(
  {
    schedule: "0 */8 * * *", // Run at minute 0 past every 8th hour
    memory: "256MiB",
    timeZone: "UTC",
    retryCount: 3,
    maxInstances: 1,
    labels: {
      job: "news-notifications",
    },
  },
  async () => {
    try {
      console.log("Starting news digest process...");

      // Get news from the last 8 hours
      const eightHoursAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 8 * 60 * 60 * 1000),
      );

      const newsSnapshot = await admin.firestore()
        .collection("news")
        .where("publishedAt", ">=", eightHoursAgo)
        .orderBy("publishedAt", "desc")
        .get();

      if (newsSnapshot.empty) {
        console.log("No news articles found in the last 8 hours");
        return;
      }

      // Group news by category
      const newsByCategory = new Map<string, number>();
      newsSnapshot.docs.forEach((doc) => {
        const category = doc.data().category || "stocks";
        newsByCategory.set(category, (newsByCategory.get(category) || 0) + 1);
      });

      // Create digest message
      let digestBody = "Latest market updates:\n";
      newsByCategory.forEach((count, category) => {
        digestBody += `${count} ${category} articles\n`;
      });

      // Send digest to all users with notifications enabled
      const users = await admin.firestore()
        .collection("users")
        .where("notificationsEnabled", "==", true)
        .where("fcmToken", "!=", null)
        .get();

      console.log(`Sending news digest to ${users.size} users`);

      for (const user of users.docs) {
        const userData = user.data() as User;
        if (userData.fcmToken) {
          const notification = {
            title: "Market News Digest 📰",
            body: digestBody.trim(),
            data: {
              type: "NEWS_DIGEST",
              count: newsSnapshot.size.toString(),
              userId: user.id,
            },
          };
          await sendPushNotification(userData.fcmToken, notification);
        }
      }

      console.log("✅ News digest sent successfully");
    } catch (error) {
      console.error("❌ Error sending news digest:", error);
    }
  },
);

/**
 * Checks asset price changes every 24 hours and sends notifications if change is more than 5%.
 */
export const checkAssetPriceChanges = onSchedule(
  {
    schedule: "0 0 * * *", // Run at midnight every day
    memory: "256MiB",
    timeZone: "UTC",
    retryCount: 3,
    maxInstances: 1,
    labels: {
      job: "price-change-notifications",
    },
  },
  async () => {
    try {
      console.log("🔄 Starting popular asset price check at:", new Date().toISOString());

      // Get all users with notifications enabled
      const users = await admin.firestore()
        .collection("users")
        .where("notificationsEnabled", "==", true)
        .where("fcmToken", "!=", null)
        .get();

      if (users.empty) {
        console.log("ℹ️ No users with notifications enabled");
        return;
      }

      console.log(`📱 Found ${users.size} users with notifications enabled`);

      // Get popular assets first
      const popularAssets = await admin.firestore()
        .collection("popularAssets")
        .get();

      if (popularAssets.empty) {
        console.log("ℹ️ No popular assets found");
        return;
      }

      console.log(`📊 Found ${popularAssets.size} popular assets`);

      // Process each user
      for (const user of users.docs) {
        try {
          const userData = user.data() as User;
          if (!userData.fcmToken) {
            console.log(`⚠️ User ${user.id} has no FCM token`);
            continue;
          }

          // Get user's portfolio assets
          const portfolioAssets = await admin.firestore()
            .collection("users")
            .doc(user.id)
            .collection("portfolio")
            .get();

          console.log(`📈 Found ${portfolioAssets.size} portfolio assets for user ${user.id}`);

          // Combine and deduplicate assets
          const assetsToCheck = new Map<string, Asset>();

          // Add portfolio assets
          portfolioAssets.docs.forEach((doc) => {
            const asset = doc.data() as PortfolioAsset;
            if (!assetsToCheck.has(asset.symbol)) {
              assetsToCheck.set(asset.symbol, {
                symbol: asset.symbol,
                name: asset.name,
                currentPrice: 0,
                lastPrice: 0,
                lastUpdated: admin.firestore.Timestamp.now(),
              });
            }
          });

          // Add popular assets
          popularAssets.docs.forEach((doc) => {
            const asset = doc.data() as Asset;
            if (!assetsToCheck.has(asset.symbol)) {
              assetsToCheck.set(asset.symbol, asset);
            }
          });

          console.log(`🔍 Checking price changes for ${assetsToCheck.size} assets`);

          // Check price changes and prepare notifications
          const notifications: Array<{
            symbol: string;
            name: string;
            change: number;
            direction: string;
            price: number;
          }> = [];

          for (const [symbol, asset] of assetsToCheck) {
            try {
              // Get current price from your price data source
              const priceDoc = await admin.firestore()
                .collection("prices")
                .doc(symbol)
                .get();

              if (!priceDoc.exists) {
                console.log(`⚠️ No price data found for ${symbol}`);
                continue;
              }

              const priceData = priceDoc.data();
              if (!priceData?.price || !priceData?.lastUpdated) {
                console.log(`⚠️ Invalid price data for ${symbol}`);
                continue;
              }

              // Check if price data is stale (older than 1 hour)
              const lastUpdated = priceData.lastUpdated.toDate();
              if (Date.now() - lastUpdated.getTime() > 60 * 60 * 1000) {
                console.log(
                  `⚠️ Stale price data for ${symbol}, last updated: ${lastUpdated.toISOString()}`
                );
                continue;
              }

              const currentPrice = priceData.price;
              const lastPrice = asset.currentPrice || currentPrice;

              // Calculate price change percentage
              const changePercent = ((currentPrice - lastPrice) / lastPrice) * 100;

              console.log(
                `📊 ${symbol}: Current: $${currentPrice}, Last: $${lastPrice}, ` +
                `Change: ${changePercent.toFixed(2)}%`
              );

              // If change is more than 5% (up or down), add to notifications
              if (Math.abs(changePercent) >= 5) {
                notifications.push({
                  symbol,
                  name: asset.name,
                  change: Math.abs(changePercent),
                  direction: changePercent > 0 ? "up" : "down",
                  price: currentPrice,
                });
              }
            } catch (error) {
              console.error(`❌ Error processing asset ${symbol}:`, error);
              continue;
            }
          }

          console.log(`📬 Preparing to send ${notifications.length} notifications to user ${user.id}`);

          // Send notifications with 1 second delay between each
          for (let i = 0; i < notifications.length; i++) {
            const notification = notifications[i];

            // Wait 1 second before sending next notification
            if (i > 0) {
              await new Promise((resolve) => setTimeout(resolve, 1000));
            }

            const emoji = notification.direction === "up" ? "📈" : "📉";
            const title = `${emoji} ${notification.symbol} Price Alert`;
            const body = `${notification.name} has moved ${notification.direction} ` +
              `by ${notification.change.toFixed(2)}% (Price: $${notification.price.toFixed(2)})`;

            const notificationPayload = {
              title,
              body,
              data: {
                type: "PRICE_CHANGE",
                symbol: notification.symbol,
                name: notification.name,
                direction: notification.direction,
                change: notification.change.toString(),
                price: notification.price.toString(),
                action: "VIEW_ASSET",
              },
            };

            try {
              await sendPushNotification(userData.fcmToken, notificationPayload);
              console.log(`✅ Price alert sent for ${notification.symbol} to user ${user.id}`);
            } catch (error) {
              console.error(`❌ Error sending price alert for ${notification.symbol}:`, error);
            }
          }
        } catch (error) {
          console.error(`❌ Error processing user ${user.id}:`, error);
          continue;
        }
      }

      console.log("✅ Asset price check completed successfully");
    } catch (error) {
      console.error("❌ Error checking asset price changes:", error);
    }
  },
);

/**
 * Syncs popular asset prices every 5 minutes.
 */
export const syncPopularAssets = onSchedule(
  {
    schedule: "*/5 * * * *", // Run every 5 minutes
    memory: "256MiB",
    timeZone: "UTC",
    retryCount: 3,
    maxInstances: 1,
    labels: {
      job: "sync-popular-assets",
    },
  },
  async () => {
    try {
      console.log("🔄 Starting popular assets sync at:", new Date().toISOString());
      // Popular crypto symbols
      const cryptoSymbols = ["BTC", "ETH", "USDT", "XRP", "BNB", "SOL", "USDC", "DOGE"];
      // Popular stock symbols
      const stockSymbols = ["AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "WMT"];

      // Batch for Firestore updates
      const batch = admin.firestore().batch();

      // Sync crypto prices
      for (const symbol of cryptoSymbols) {
        try {
          const response = await axios.get(
            "https://pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest",
            {
              params: {
                symbol: symbol,
                convert: "USD",
              },
              headers: {
                "X-CMC_PRO_API_KEY": process.env.COINMARKETCAP_API_KEY,
              },
            }
          );

          if (response.data?.data?.[symbol]) {
            const crypto = response.data.data[symbol];
            const usdQuote = crypto.quote.USD;

            const assetRef = admin.firestore()
              .collection("popularAssets")
              .doc(symbol);

            batch.set(assetRef, {
              symbol: symbol,
              name: crypto.name,
              type: "crypto",
              currentPrice: usdQuote.price,
              lastPrice: (await assetRef.get()).data()?.currentPrice || usdQuote.price,
              priceChangePercentage24H: usdQuote.percent_change_24h,
              marketCap: usdQuote.market_cap,
              volume24H: usdQuote.volume_24h,
              lastUpdated: admin.firestore.Timestamp.now(),
            }, {merge: true});

            console.log(`✅ Updated crypto price for ${symbol}: $${usdQuote.price}`);
          }
        } catch (error) {
          console.error(`❌ Error updating crypto ${symbol}:`, error);
          continue;
        }
      }

      // Sync stock prices
      for (const symbol of stockSymbols) {
        try {
          const response = await axios.get(
            "https://finnhub.io/api/v1/quote",
            {
              params: {
                symbol: symbol,
                token: process.env.FINNHUB_API_KEY,
              },
            }
          );

          if (response.data?.c) { // Current price
            const stock = response.data;
            const assetRef = admin.firestore()
              .collection("popularAssets")
              .doc(symbol);

            const priceChange24H = ((stock.c - stock.pc) / stock.pc) * 100;

            batch.set(assetRef, {
              symbol: symbol,
              type: "stock",
              currentPrice: stock.c,
              lastPrice: (await assetRef.get()).data()?.currentPrice || stock.c,
              priceChangePercentage24H: priceChange24H,
              high24H: stock.h,
              low24H: stock.l,
              lastUpdated: admin.firestore.Timestamp.now(),
            }, {merge: true});

            console.log(`✅ Updated stock price for ${symbol}: $${stock.c}`);
          }
        } catch (error) {
          console.error(`❌ Error updating stock ${symbol}:`, error);
          continue;
        }
      }

      // Commit all updates
      await batch.commit();
      console.log("✅ Successfully synced all popular asset prices");

      // Update sync status
      await admin.firestore()
        .collection("system")
        .doc("priceSync")
        .set({
          lastSync: admin.firestore.Timestamp.now(),
          status: "success",
        }, {merge: true});
    } catch (error) {
      console.error("❌ Error syncing popular assets:", error);
      // Update sync status on error
      await admin.firestore()
        .collection("system")
        .doc("priceSync")
        .set({
          lastSync: admin.firestore.Timestamp.now(),
          status: "error",
          error: error instanceof Error ? error.message : String(error),
        }, {merge: true});
    }
  },
);
