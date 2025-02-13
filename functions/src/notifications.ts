import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

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
      console.log("🔄 Starting asset price check at:", new Date().toISOString());

      // Get all users with notifications enabled
      const users = await admin.firestore()
        .collection("users")
        .where("notificationsEnabled", "==", true)
        .get();

      if (users.empty) {
        console.log("ℹ️ No users with notifications enabled");
        return;
      }

      // Process each user
      for (const user of users.docs) {
        try {
          const userData = user.data() as User;
          if (!userData.fcmToken) continue;

          // Get user's portfolio assets
          const portfolioAssets = await admin.firestore()
            .collection("users")
            .doc(user.id)
            .collection("portfolio")
            .get();

          // Get popular assets
          const popularAssets = await admin.firestore()
            .collection("popularAssets")
            .get();

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

          // Check price changes and prepare notifications
          const notifications: Array<{
            symbol: string;
            name: string;
            change: number;
            direction: string;
            price: number;
          }> = [];

          for (const [symbol, asset] of assetsToCheck) {
            // Get current price from your price data source
            const priceDoc = await admin.firestore()
              .collection("prices")
              .doc(symbol)
              .get();

            if (!priceDoc.exists) continue;

            const currentPrice = priceDoc.data()?.price || 0;
            const lastPrice = asset.currentPrice || currentPrice;

            // Calculate price change percentage
            const changePercent = ((currentPrice - lastPrice) / lastPrice) * 100;

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
          }

          // Send notifications with 1 second delay between each
          for (let i = 0; i < notifications.length; i++) {
            const notification = notifications[i];

            // Wait 1 second before sending next notification
            if (i > 0) {
              await new Promise((resolve) => setTimeout(resolve, 1000));
            }

            // Get current badge count
            const userDoc = await admin.firestore()
              .collection("users")
              .doc(user.id)
              .get();

            const currentBadge = userDoc.data()?.badgeCount || 0;
            const newBadgeCount = currentBadge + 1;

            // Update badge count in Firestore
            await admin.firestore()
              .collection("users")
              .doc(user.id)
              .update({
                badgeCount: newBadgeCount,
                lastNotificationAt: admin.firestore.Timestamp.now(),
              });

            // Send notification
            await admin.messaging().send({
              token: userData.fcmToken,
              notification: {
                title: `${notification.symbol} Price Alert 📊`,
                body: [
                  `${notification.name} has moved ${notification.direction}`,
                  `by ${notification.change.toFixed(2)}%`,
                  `(Price: $${notification.price.toFixed(2)})`,
                ].join(" "),
              },
              data: {
                type: "PRICE_CHANGE",
                symbol: notification.symbol,
                name: notification.name,
                direction: notification.direction,
                change: notification.change.toString(),
                price: notification.price.toString(),
              },
              android: {
                priority: "high",
              },
              apns: {
                payload: {
                  aps: {
                    contentAvailable: true,
                    sound: "default",
                    badge: newBadgeCount,
                    mutableContent: true,
                  },
                },
              },
            });

            console.log(`✅ Sent price alert for ${notification.symbol} to user ${user.id}`);
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
 * Sends price change alerts every 24 hours for significant changes (>5%).
 */
export const sendPriceAlerts = onSchedule(
  {
    schedule: "0 0 * * *", // Run at 00:00 UTC every day
    memory: "256MiB",
    timeZone: "UTC",
    retryCount: 3,
    maxInstances: 1,
    labels: {
      job: "price-alerts",
    },
  },
  async () => {
    try {
      console.log("🔄 Starting daily price change check...");

      // Get all assets
      const assetsSnapshot = await admin.firestore()
        .collection("assets")
        .get();

      const significantChanges: Array<{
        symbol: string;
        name: string;
        priceChange: number;
        currentPrice: number;
      }> = [];

      // Check each asset for significant price changes
      assetsSnapshot.forEach((doc) => {
        const asset = doc.data() as Asset;
        if (!asset.currentPrice || !asset.lastPrice) return;

        const priceChange = ((asset.currentPrice - asset.lastPrice) / asset.lastPrice) * 100;

        // If price change is more than 5% (positive or negative)
        if (Math.abs(priceChange) >= 5) {
          significantChanges.push({
            symbol: asset.symbol,
            name: asset.name,
            priceChange: priceChange,
            currentPrice: asset.currentPrice,
          });
        }
      });

      if (significantChanges.length === 0) {
        console.log("No significant price changes found");
        return;
      }

      console.log(`Found ${significantChanges.length} assets with significant price changes`);

      // Get all users with notifications enabled
      const users = await admin.firestore()
        .collection("users")
        .where("notificationsEnabled", "==", true)
        .where("fcmToken", "!=", null)
        .get();

      // Send notifications to each user
      for (const user of users.docs) {
        const userData = user.data() as User;
        if (!userData.fcmToken) continue;

        // Create notification for each significant change
        for (const change of significantChanges) {
          const direction = change.priceChange > 0 ? "increased" : "decreased";
          const emoji = change.priceChange > 0 ? "📈" : "📉";

          const notification = {
            title: `${emoji} ${change.symbol} Price Alert`,
            body: `${change.name} has ${direction} by ${Math.abs(change.priceChange).toFixed(2)}% ` +
              `in the last 24 hours. Current price: $${change.currentPrice.toFixed(2)}`,
            data: {
              type: "PRICE_ALERT",
              action: "VIEW_ASSET",
              symbol: change.symbol,
              priceChange: change.priceChange.toString(),
              currentPrice: change.currentPrice.toString(),
            },
          };

          try {
            await sendPushNotification(userData.fcmToken, notification);
            console.log(`✅ Price alert sent for ${change.symbol} to user ${user.id}`);
          } catch (error) {
            console.error(`❌ Error sending price alert for ${change.symbol}:`, error);
          }

          // Add a small delay between notifications to prevent rate limiting
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      }

      console.log("✅ Price alert notifications completed");
    } catch (error) {
      console.error("❌ Error in price alert process:", error);
    }
  },
);
