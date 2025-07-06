const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// HTTP function to check username/email
exports.checkUserExists = functions.https.onCall(async (data, context) => {
  const { username, email } = data;

  if (!username && !email) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Either username or email must be provided.'
    );
  }

  let usernameExists = false;
  let emailExists = false;

  if (username) {
    const usernameSnapshot = await db.collection('users')
      .where('username', '==', username)
      .limit(1)
      .get();

    usernameExists = !usernameSnapshot.empty;
  }

  if (email) {
    const emailSnapshot = await db.collection('users')
      .where('email', '==', email)
      .limit(1)
      .get();

    emailExists = !emailSnapshot.empty;
  }

  return { usernameExists, emailExists };
});
