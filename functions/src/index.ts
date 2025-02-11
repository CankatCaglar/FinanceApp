/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import * as admin from "firebase-admin";

// Initialize Firebase Admin
admin.initializeApp();

// Re-export functions from notifications.ts
export {
  onNewUserWelcome,
  onUserSession,
  sendNewsNotifications,
  checkAssetPriceChanges,
} from "./notifications";

// Re-export functions from newsSync.ts
export {syncNews} from "./newsSync";
