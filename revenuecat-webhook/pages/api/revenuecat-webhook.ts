import { NextApiRequest, NextApiResponse } from "next"; import crypto from "crypto"; import * as admin from "firebase-admin"; if (!admin.apps.length) { admin.initializeApp({ credential: admin.credential.cert({ projectId: process.env.FIREBASE_PROJECT_ID, clientEmail: process.env.FIREBASE_CLIENT_EMAIL, privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\n/g, "
"), }), }); } const db = admin.firestore(); interface RevenueCatEvent { type: string; event: { original_transaction_id: string; transaction_id: string; product_id: string; subscriber: { original_app_user_id: string; subscriptions: { [key: string]: { expires_date: string; period_type: string; }; }; }; }; } function verifyRevenueCatSignature(payload: string, signature: string): boolean { try { const secret = process.env.REVENUECAT_WEBHOOK_SECRET; if (!secret) { console.error("RevenueCat webhook secret is not configured"); return false; } const hmac = crypto.createHmac("sha256", secret); const digest = hmac.update(payload).digest("hex"); return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest)); } catch (error) { console.error("Signature verification error:", error); return false; } } async function updateUserSubscription(userId: string, subscriptionData: any, eventType: string) { try { const userRef = db.collection("users").doc(userId); const subscriptionRef = db.collection("subscriptions").doc(userId); const batch = db.batch(); batch.update(userRef, { subscriptionStatus: eventType === "CANCELLATION" ? "cancelled" : "active", subscriptionType: subscriptionData.product_id, lastUpdated: admin.firestore.FieldValue.serverTimestamp(), }); batch.set(subscriptionRef, { status: eventType === "CANCELLATION" ? "cancelled" : "active", productId: subscriptionData.product_id, originalTransactionId: subscriptionData.original_transaction_id, transactionId: subscriptionData.transaction_id, expiresDate: subscriptionData.expires_date, lastUpdated: admin.firestore.FieldValue.serverTimestamp(), eventType: eventType, }, { merge: true }); await batch.commit(); console.log(`✅ Successfully updated subscription for user ${userId}`); } catch (error) { console.error(`❌ Error updating subscription for user ${userId}:`, error); throw error; } } export default async function handler(req: NextApiRequest, res: NextApiResponse) { if (req.method !== "POST") { return res.status(405).json({ error: "Method not allowed" }); } try { const signature = req.headers["x-revenuecat-signature"]; if (!signature || Array.isArray(signature)) { return res.status(400).json({ error: "Invalid signature header" }); } const rawBody = JSON.stringify(req.body); if (!verifyRevenueCatSignature(rawBody, signature)) { return res.status(401).json({ error: "Invalid signature" }); } const event = req.body as RevenueCatEvent; const userId = event.event.subscriber.original_app_user_id; console.log(`📥 Received RevenueCat webhook: ${event.type} for user ${userId}`); switch (event.type) { case "INITIAL_PURCHASE": case "RENEWAL": case "NON_RENEWING_PURCHASE": await updateUserSubscription(userId, event.event, event.type); break; case "CANCELLATION": await updateUserSubscription(userId, event.event, "CANCELLATION"); break; case "UNCANCELLATION": await updateUserSubscription(userId, event.event, "ACTIVE"); break; case "BILLING_ISSUE": const userRef = db.collection("users").doc(userId); await userRef.update({ hasBillingIssue: true, billingIssueDate: admin.firestore.FieldValue.serverTimestamp(), }); break; default: console.log(`⚠️ Unhandled event type: ${event.type}`); } return res.status(200).json({ success: true, message: `Successfully processed ${event.type} event for user ${userId}` }); } catch (error) { console.error("❌ Webhook error:", error); return res.status(500).json({ error: "Internal server error", message: error instanceof Error ? error.message : "Unknown error" }); } }
