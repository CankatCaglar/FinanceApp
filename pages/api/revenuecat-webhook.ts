import { NextApiRequest, NextApiResponse } from "next";
import crypto from "crypto";
import * as admin from "firebase-admin";

// Firebase admin initialization
if (!admin.apps.length) {
  console.log("🔄 Initializing Firebase Admin SDK");
  try {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      }),
    });
    console.log("✅ Firebase Admin SDK initialized successfully");
  } catch (error) {
    console.error("❌ Failed to initialize Firebase Admin SDK:", error);
    throw error;
  }
}

const db = admin.firestore();

interface RevenueCatEvent {
  type: string;
  event: {
    original_transaction_id: string;
    transaction_id: string;
    product_id: string;
    subscriber: {
      original_app_user_id: string;
      subscriptions: {
        [key: string]: {
          expires_date: string;
          period_type: string;
        };
      };
    };
  };
}

function verifyRevenueCatSignature(payload: string, signature: string): boolean {
  console.log("🔐 Verifying RevenueCat signature");
  try {
    const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
    if (!secret) {
      console.error("❌ RevenueCat webhook secret is not configured");
      return false;
    }

    const hmac = crypto.createHmac("sha256", secret);
    const digest = hmac.update(payload).digest("hex");
    const isValid = crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest));
    
    console.log(isValid ? "✅ Signature verification successful" : "❌ Signature verification failed");
    return isValid;
  } catch (error) {
    console.error("❌ Signature verification error:", error);
    return false;
  }
}

async function updateUserSubscription(
  userId: string,
  subscriptionData: any,
  eventType: string
) {
  console.log(`🔄 Updating subscription for user ${userId}`, {
    eventType,
    productId: subscriptionData.product_id,
    transactionId: subscriptionData.transaction_id
  });

  try {
    const userRef = db.collection("users").doc(userId);
    const subscriptionRef = db.collection("subscriptions").doc(userId);

    // Verify user exists
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found in database`);
      throw new Error(`User ${userId} not found`);
    }

    console.log(`📝 Creating batch write operation for user ${userId}`);
    const batch = db.batch();

    // Update user document
    const userUpdate = {
      subscriptionStatus: eventType === "CANCELLATION" ? "cancelled" : "active",
      subscriptionType: subscriptionData.product_id,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    };
    console.log(`📝 User document update data:`, userUpdate);
    batch.update(userRef, userUpdate);

    // Update subscription document
    const subscriptionUpdate = {
      status: eventType === "CANCELLATION" ? "cancelled" : "active",
      productId: subscriptionData.product_id,
      originalTransactionId: subscriptionData.original_transaction_id,
      transactionId: subscriptionData.transaction_id,
      expiresDate: subscriptionData.expires_date,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      eventType: eventType,
    };
    console.log(`📝 Subscription document update data:`, subscriptionUpdate);
    batch.set(subscriptionRef, subscriptionUpdate, { merge: true });

    await batch.commit();
    console.log(`✅ Successfully updated subscription for user ${userId}`);
  } catch (error) {
    console.error(`❌ Error updating subscription for user ${userId}:`, error);
    throw error;
  }
}

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  console.log('📥 Received webhook request', {
    method: req.method,
    url: req.url,
    headers: {
      'content-type': req.headers['content-type'],
      'x-revenuecat-signature': req.headers['x-revenuecat-signature']?.substring(0, 10) + '...',
    }
  });

  if (req.method !== "POST") {
    console.log('❌ Method not allowed:', req.method);
    return res.status(405).json({ error: "Method not allowed" });
  }

  try {
    const signature = req.headers["x-revenuecat-signature"];
    if (!signature || Array.isArray(signature)) {
      console.log('❌ Invalid signature header');
      return res.status(400).json({ error: "Invalid signature header" });
    }

    const rawBody = JSON.stringify(req.body);
    console.log('📦 Request body:', rawBody);

    if (!verifyRevenueCatSignature(rawBody, signature)) {
      console.log('❌ Invalid signature');
      return res.status(401).json({ error: "Invalid signature" });
    }

    const event = req.body as RevenueCatEvent;
    const userId = event.event.subscriber.original_app_user_id;

    console.log(`📥 Processing RevenueCat webhook:`, {
      type: event.type,
      userId: userId,
      productId: event.event.product_id,
      transactionId: event.event.transaction_id
    });

    switch (event.type) {
      case "INITIAL_PURCHASE":
        console.log(`🆕 Processing initial purchase for user ${userId}`);
        await updateUserSubscription(userId, event.event, event.type);
        break;

      case "RENEWAL":
        console.log(`🔄 Processing renewal for user ${userId}`);
        await updateUserSubscription(userId, event.event, event.type);
        break;

      case "NON_RENEWING_PURCHASE":
        console.log(`💰 Processing non-renewing purchase for user ${userId}`);
        await updateUserSubscription(userId, event.event, event.type);
        break;

      case "CANCELLATION":
        console.log(`❌ Processing cancellation for user ${userId}`);
        await updateUserSubscription(userId, event.event, "CANCELLATION");
        break;

      case "UNCANCELLATION":
        console.log(`✅ Processing uncancellation for user ${userId}`);
        await updateUserSubscription(userId, event.event, "ACTIVE");
        break;

      case "BILLING_ISSUE":
        console.log(`⚠️ Processing billing issue for user ${userId}`);
        const userRef = db.collection("users").doc(userId);
        await userRef.update({
          hasBillingIssue: true,
          billingIssueDate: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`✅ Updated billing issue status for user ${userId}`);
        break;

      default:
        console.log(`⚠️ Unhandled event type: ${event.type}`);
    }

    console.log('✅ Successfully processed webhook');
    return res.status(200).json({ 
      success: true,
      message: `Successfully processed ${event.type} event for user ${userId}`
    });

  } catch (error) {
    console.error("❌ Webhook error:", error);
    // Log the full error details
    if (error instanceof Error) {
      console.error({
        name: error.name,
        message: error.message,
        stack: error.stack,
      });
    }
    return res.status(500).json({ 
      error: "Internal server error",
      message: error instanceof Error ? error.message : "Unknown error"
    });
  }
}
