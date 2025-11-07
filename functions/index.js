const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {onRequest} = require("firebase-functions/v2/https");

// Initialize Firebase Admin SDK (only once)
admin.initializeApp();

// ============================================
// 1. NEW BOOKING NOTIFICATION (FCM Push)
// ============================================
exports.sendBookingNotification = onDocumentCreated(
  "appointments/{appointmentId}",
  async (event) => {
    try {
      const appointmentData = event.data.data();
      const appointmentId = event.params.appointmentId;

      console.log("📱 New appointment created:", appointmentId);

      // Get artist reference
      const artistRef = appointmentData.artist_id;
      if (!artistRef) {
        console.log("❌ No artist reference found");
        return;
      }

      // Get artist document to find user_id
      const artistDoc = await artistRef.get();
      if (!artistDoc.exists) {
        console.log("❌ Artist document not found");
        return;
      }

      const artistData = artistDoc.data();
      const userRef = artistData.user_id;

      if (!userRef) {
        console.log("❌ No user reference in artist document");
        return;
      }

      // Get user document to find FCM token
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        console.log("❌ User document not found");
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        console.log("⚠️ No FCM token found for user");
        return;
      }

      // Get customer details
      const customerRef = appointmentData.customerId;
      const customerDoc = await customerRef.get();
      const customerName = customerDoc.exists ?
        customerDoc.data().name || "A customer" : "A customer";

      // Prepare notification body
      const notificationBody =
        `${customerName} has booked ${appointmentData.category} ` +
        `on ${appointmentData.date} at ${appointmentData.time}`;

      // Prepare notification
      const message = {
        notification: {
          title: "🎉 New Booking!",
          body: notificationBody,
        },
        data: {
          appointmentId: appointmentId,
          date: appointmentData.date,
          time: appointmentData.time,
          category: appointmentData.category,
          type: "new_booking",
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "booking_channel",
            sound: "default",
            priority: "high",
            icon: "@mipmap/ic_launcher",
            color: "#B968C7",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      // Send notification
      const response = await admin.messaging().send(message);
      console.log("✅ New booking notification sent successfully:", response);

      return {success: true, messageId: response};
    } catch (error) {
      console.error("❌ Error sending new booking notification:", error);
      return {success: false, error: error.message};
    }
  },
);

// ============================================
// 2. CANCELLATION NOTIFICATION (FCM Push)
// ============================================
exports.sendCancellationNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    try {
      const notificationData = event.data.data();
      const notificationId = event.params.notificationId;
      const notificationType = notificationData.type;

      console.log("🔔 New notification created:", notificationId);
      console.log("Notification type:", notificationType);

      // Only handle booking_cancelled notifications
      if (notificationType !== "booking_cancelled") {
        console.log("ℹ️ Not a cancellation notification, skipping");
        return;
      }

      // Get references
      const recipientRef = notificationData.recipient_id;
      const customerRef = notificationData.customer_id;
      const appointmentRef = notificationData.appointment_id;

      if (!recipientRef || !customerRef || !appointmentRef) {
        console.log("❌ Missing required references");
        return;
      }

      // Get recipient (artist) details
      const recipientDoc = await recipientRef.get();
      if (!recipientDoc.exists) {
        console.log("❌ Recipient document not found");
        return;
      }

      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;

      if (!fcmToken) {
        console.log("⚠️ No FCM token found for recipient");
        return;
      }

      // Get customer details
      const customerDoc = await customerRef.get();
      if (!customerDoc.exists) {
        console.log("❌ Customer document not found");
        return;
      }

      const customerData = customerDoc.data();
      const customerName = customerData.name || "A customer";

      // Get appointment details
      const appointmentDoc = await appointmentRef.get();
      if (!appointmentDoc.exists) {
        console.log("❌ Appointment document not found");
        return;
      }

      const appointmentData = appointmentDoc.data();
      const category = appointmentData.category || "appointment";
      const date = appointmentData.date || "";
      const time = appointmentData.time || "";

      // Prepare notification message
      const notificationTitle = "Booking Cancelled";
      const notificationBody =
        `${customerName} cancelled their ${category}` +
        ` booking on ${date} at ${time}`;

      // Prepare FCM message
      const message = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          type: "booking_cancelled",
          notificationId: notificationId,
          appointmentId: appointmentRef.id,
          customerId: customerRef.id,
          customerName: customerName,
          category: category,
          date: date,
          time: time,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "booking_channel",
            sound: "default",
            priority: "high",
            icon: "@mipmap/ic_launcher",
            color: "#FF0000",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              alert: {
                title: notificationTitle,
                body: notificationBody,
              },
            },
          },
        },
      };

      // Send notification
      const response = await admin.messaging().send(message);
      console.log("✅ Cancellation notification sent successfully:", response);

      return {success: true, messageId: response};
    } catch (error) {
      console.error("❌ Error sending cancellation notification:", error);
      return {success: false, error: error.message};
    }
  },
);

// ============================================
// 3. CHAT MESSAGE NOTIFICATION (FCM Push)
// ============================================
exports.sendChatNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    try {
      const messageData = event.data.data();
      const chatId = event.params.chatId;
      const messageId = event.params.messageId;

      console.log("💬 New chat message created:", messageId);
      console.log("Chat ID:", chatId);

      // Get sender and receiver references
      const senderRef = messageData.senderRef;
      const receiverRef = messageData.receiverRef;

      if (!senderRef || !receiverRef) {
        console.log("❌ Missing sender or receiver reference");
        return;
      }

      // Get sender details
      const senderDoc = await senderRef.get();
      if (!senderDoc.exists) {
        console.log("❌ Sender document not found");
        return;
      }

      const senderData = senderDoc.data();
      const senderName = senderData.name || "Someone";
      const senderProfilePic = senderData.profilePic || "";

      // Get receiver details (to get FCM token)
      const receiverDoc = await receiverRef.get();
      if (!receiverDoc.exists) {
        console.log("❌ Receiver document not found");
        return;
      }

      const receiverData = receiverDoc.data();
      const fcmToken = receiverData.fcmToken;

      if (!fcmToken) {
        console.log("⚠️ No FCM token found for receiver");
        return;
      }

      // Prepare notification body based on message type
      const messageType = messageData.messageType || "text";
      const messageContent = messageData.message || "";

      let notificationBody;
      if (messageType === "image") {
        notificationBody = "📷 Sent a photo";
      } else {
        // Truncate long messages
        notificationBody = messageContent.length > 100 ?
          messageContent.substring(0, 100) + "..." :
          messageContent;
      }

      // Prepare notification
      const message = {
        notification: {
          title: senderName,
          body: notificationBody,
        },
        data: {
          chatId: chatId,
          messageId: messageId,
          senderId: senderRef.id,
          senderName: senderName,
          senderProfilePic: senderProfilePic,
          messageType: messageType,
          type: "chat_message",
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "chat_channel",
            sound: "default",
            priority: "high",
            icon: "@mipmap/ic_launcher",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              alert: {
                title: senderName,
                body: notificationBody,
              },
            },
          },
        },
      };

      // Send notification
      const response = await admin.messaging().send(message);
      console.log("✅ Chat notification sent successfully:", response);

      return {success: true, messageId: response};
    } catch (error) {
      console.error("❌ Error sending chat notification:", error);
      return {success: false, error: error.message};
    }
  },
);

// ============================================
// 4. SEND OTP EMAIL (Callable Function)
// ============================================
exports.sendOtpEmail = onCall(
  {
    invoker: "public",
    secrets: ["SMTP_HOST", "SMTP_USER", "SMTP_PASS", "FROM_EMAIL"],
  },
  async (request) => {
    console.log("============================================");
    console.log("🚀 sendOtpEmail function invoked");
    console.log("============================================");

    const {email, otp} = request.data;

    console.log("📧 Email:", email);
    console.log("🔢 OTP received:", otp ? "YES" : "NO");
    console.log("🔐 Auth object:", request.auth ? "PRESENT" : "MISSING");

    if (!email || !otp) {
      console.error("❌ Missing required fields");
      throw new HttpsError(
        "invalid-argument",
        "Email and OTP are required",
      );
    }

    if (!request.auth) {
      console.error("❌ Unauthenticated request received");
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to send OTP",
      );
    }

    const userId = request.auth.uid;
    console.log("✅ Authenticated user ID:", userId);

    try {
      const userDoc = await admin.firestore()
        .collection("users")
        .doc(userId)
        .get();

      if (!userDoc.exists) {
        console.error("❌ User document not found in Firestore");
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data();
      console.log("📋 User data found, checking email match...");

      if (userData.email !== email) {
        console.error("❌ Email mismatch!");
        throw new HttpsError(
          "permission-denied",
          "Email does not match user record",
        );
      }

      console.log("✅ Email verified successfully");
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("❌ Error validating user:", error);
      throw new HttpsError("internal", "Failed to validate user");
    }

    const smtpHost = process.env.SMTP_HOST;
    const smtpPort = process.env.SMTP_PORT || 587;
    const smtpUser = process.env.SMTP_USER;
    const smtpPass = process.env.SMTP_PASS;
    const fromEmail = process.env.FROM_EMAIL || smtpUser;

    console.log("📮 SMTP Configuration:");
    console.log("   Host:", smtpHost ? "✓" : "✗");
    console.log("   Port:", smtpPort);

    if (!smtpHost || !smtpUser || !smtpPass) {
      console.error("❌ Missing SMTP credentials");
      throw new HttpsError(
        "failed-precondition",
        "SMTP credentials not configured",
      );
    }

    console.log("🔧 Creating email transporter...");
    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: parseInt(smtpPort),
      secure: smtpPort === "465",
      auth: {
        user: smtpUser,
        pass: smtpPass,
      },
      tls: {
        rejectUnauthorized: true,
        minVersion: "TLSv1.2",
      },
    });

    const htmlContent = `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header {
          background: linear-gradient(135deg, #C367CA 0%, #FB81EE 100%);
          color: white;
          padding: 30px;
          text-align: center;
          border-radius: 10px 10px 0 0;
        }
        .content {
          background: #f9f9f9;
          padding: 30px;
          border-radius: 0 0 10px 10px;
        }
        .otp-code {
          background: white;
          border: 2px dashed #C367CA;
          padding: 20px;
          text-align: center;
          font-size: 30px;
          font-weight: bold;
          letter-spacing: 8px;
          color: #C367CA;
          margin: 20px 0;
          border-radius: 8px;
        }
        .footer {
          text-align: center;
          margin-top: 20px;
          color: #666;
          font-size: 12px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>BlushUp Verification</h1>
        </div>
        <div class="content">
          <h2>Hello!</h2>
          <p>You requested to log in to your BlushUp account.
          Please use the verification code below:</p>
          <div class="otp-code">${otp}</div>
          <p><strong>This code will expire in 5 minutes.</strong></p>
          <p>If you didn't request this code,
          please ignore this email.</p>
          <div class="footer">
            <p>This is an automated email, please do not reply.</p>
          </div>
        </div>
      </div>
    </body>
    </html>
  `;

    const mailOptions = {
      from: `"BlushUp" <${fromEmail}>`,
      to: email,
      subject: "BlushUp - Your Verification Code",
      text: `Your OTP code is ${otp}. It will expire in 5 minutes.`,
      html: htmlContent,
    };

    try {
      console.log("📤 Sending email...");
      const info = await transporter.sendMail(mailOptions);
      console.log(`✅ Email sent successfully!`);
      console.log(`   Message ID: ${info.messageId}`);
      console.log("============================================");

      return {success: true, messageId: info.messageId};
    } catch (error) {
      console.error("============================================");
      console.error("❌ SMTP ERROR:");
      console.error("   Message:", error.message);
      console.error("============================================");

      throw new HttpsError(
        "internal",
        `Failed to send email: ${error.message}`,
      );
    }
  },
);

// ============================================
// 5. SEND MAKEUP ARTIST STATUS EMAIL
// ============================================
exports.sendMakeupArtistStatusEmail = onCall(
  {
    invoker: "public",
    secrets: ["SMTP_HOST", "SMTP_USER", "SMTP_PASS", "FROM_EMAIL"],
  },
  async (request) => {
    console.log("============================================");
    console.log("🎨 sendMakeupArtistStatusEmail function invoked");
    console.log("============================================");

    const {email, artistName, status} = request.data;

    console.log("📧 Email:", email);
    console.log("👤 Artist Name:", artistName);
    console.log("📊 Status:", status);
    console.log("🔐 Auth object:", request.auth ? "PRESENT" : "MISSING");

    // Validate input
    if (!email || !artistName || !status) {
      console.error("❌ Missing required fields");
      throw new HttpsError(
        "invalid-argument",
        "Email, artist name, and status are required",
      );
    }

    // Verify user is authenticated (admin)
    if (!request.auth) {
      console.error("❌ Unauthenticated request received");
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to send status emails",
      );
    }

    const userId = request.auth.uid;
    console.log("✅ Authenticated user ID:", userId);

    // Verify the user is an admin
    try {
      const userDoc = await admin.firestore()
        .collection("users")
        .doc(userId)
        .get();

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data();

      // Check if user is admin
      if (userData.role !== "admin") {
        console.error("❌ User is not an admin");
        throw new HttpsError(
          "permission-denied",
          "Only admins can send status emails",
        );
      }

      console.log("✅ Admin verified successfully");
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("❌ Error validating admin:", error);
      throw new HttpsError("internal", "Failed to validate admin");
    }

    // Get SMTP config
    const smtpHost = process.env.SMTP_HOST;
    const smtpPort = process.env.SMTP_PORT || 587;
    const smtpUser = process.env.SMTP_USER;
    const smtpPass = process.env.SMTP_PASS;
    const fromEmail = process.env.FROM_EMAIL || smtpUser;

    console.log("📮 SMTP Configuration:");
    console.log("   Host:", smtpHost ? "✓" : "✗");
    console.log("   Port:", smtpPort);

    if (!smtpHost || !smtpUser || !smtpPass) {
      console.error("❌ Missing SMTP credentials");
      throw new HttpsError(
        "failed-precondition",
        "SMTP credentials not configured",
      );
    }

    // Email template functions
    const getApproveEmailTemplate = (name) => `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            color: #333;
          }
          .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
          }
          .header {
            background-color: #4CAF50;
            color: white;
            padding: 20px;
            text-align: center;
            border-radius: 8px 8px 0 0;
          }
          .content {
            background-color: #f9f9f9;
            padding: 20px;
            border-radius: 0 0 8px 8px;
          }
          .status { font-weight: bold; color: #4CAF50; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🎉 Congratulations! Application Approved</h1>
          </div>
          <div class="content">
            <p>Dear ${name},</p>
            <p>We are thrilled to inform you that your makeup artist
            application has been <span class="status">APPROVED</span>!</p>
            <p><strong>Welcome to the BlushUp family!</strong> You can
            now start accepting bookings and showcase your talent to our
            clients.</p>
            <p><strong>What's next?</strong></p>
            <ul>
              <li>✅ Log in to your account to access your artist
              dashboard</li>
              <li>🎨 Update your portfolio with your best work</li>
              <li>💰 Set your availability and pricing</li>
              <li>📱 Start receiving booking requests from clients</li>
            </ul>
            <p>We're excited to see the amazing transformations you'll
            create!</p>
            <p>If you have any questions, our support team is here to
            help:</p>
            <p>📧 Email: seejiawei39@gmail.com</p>
            <p>📞 Phone: 018-3584968</p>
            <p>Best regards,<br>The BlushUp Team</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const getRejectEmailTemplate = (name) => `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            color: #333;
          }
          .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
          }
          .header {
            background-color: #F44336;
            color: white;
            padding: 20px;
            text-align: center;
            border-radius: 8px 8px 0 0;
          }
          .content {
            background-color: #f9f9f9;
            padding: 20px;
            border-radius: 0 0 8px 8px;
          }
          .status { font-weight: bold; color: #F44336; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Application Status Update</h1>
          </div>
          <div class="content">
            <p>Dear ${name},</p>
            <p>Thank you for your interest in joining BlushUp as a
            makeup artist.</p>
            <p>After careful review, we regret to inform you that your
            application has been
            <span class="status">REJECTED</span> at this time.</p>
            <p><strong>This is not the end of your journey with us!
            </strong> We encourage you to reapply in the future once
            you have enhanced the following areas:</p>
            <ul>
              <li>📸 Portfolio quality and variety - showcase diverse
              makeup styles</li>
              <li>💼 Professional experience and certifications</li>
              <li>🗺️ Service area coverage and availability</li>
              <li>📋 Complete profile information</li>
            </ul>
            <p>We believe in supporting aspiring makeup artists and
            would love to see you succeed. Please don't hesitate to
            reach out if you need guidance on improving your
            application.</p>
            <p>For support and guidance:</p>
            <p>📧 Email: seejiawei39@gmail.com</p>
            <p>📞 Phone: 018-3584968</p>
            <p>Thank you for your understanding.</p>
            <p>Best regards,<br>The BlushUp Team</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const getDisableEmailTemplate = (name) => `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            color: #333;
          }
          .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
          }
          .header {
            background-color: #FF9800;
            color: white;
            padding: 20px;
            text-align: center;
            border-radius: 8px 8px 0 0;
          }
          .content {
            background-color: #f9f9f9;
            padding: 20px;
            border-radius: 0 0 8px 8px;
          }
          .warning { color: #FF9800; font-weight: bold; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>⚠️ Account Temporarily Disabled</h1>
          </div>
          <div class="content">
            <p>Dear ${name},</p>
            <p>We are writing to inform you that your BlushUp account
            has been
            <span class="warning">TEMPORARILY DISABLED</span>.</p>
            <p><strong>What this means:</strong></p>
            <ul>
              <li>🚫 Your account access has been suspended</li>
              <li>🔒 You cannot log in to the platform temporarily</li>
              <li>👁️ Your profile is not visible to clients</li>
              <li>📅 No new bookings can be made</li>
            </ul>
            <p><strong>Next Steps:</strong></p>
            <p>This action may be temporary. Please contact our support
            team immediately to discuss your account status and
            potential reactivation.</p>
            <p>Our team is here to help resolve any issues:</p>
            <p>📧 Email: seejiawei39@gmail.com</p>
            <p>📞 Phone: 018-3584968</p>
            <p>We value your partnership and hope to resolve this
            matter quickly.</p>
            <p>Best regards,<br>The BlushUp Team</p>
          </div>
        </div>
      </body>
      </html>
    `;

    // Determine email content based on status
    let emailSubject;
    let emailBody;

    const normalizedStatus = status.toLowerCase();

    switch (normalizedStatus) {
    case "approved":
    case "accepted":
      emailSubject = "🎉 Application Approved - Welcome to BlushUp!";
      emailBody = getApproveEmailTemplate(artistName);
      break;
    case "rejected":
      emailSubject = "Application Status Update";
      emailBody = getRejectEmailTemplate(artistName);
      break;
    case "disabled":
      emailSubject = "⚠️ Account Status - Action Required";
      emailBody = getDisableEmailTemplate(artistName);
      break;
    default:
      emailSubject = `Application Status Update - ${status}`;
      emailBody = getApproveEmailTemplate(artistName);
    }

    // Create transporter
    console.log("🔧 Creating email transporter...");
    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: parseInt(smtpPort),
      secure: smtpPort === "465",
      auth: {
        user: smtpUser,
        pass: smtpPass,
      },
      tls: {
        rejectUnauthorized: true,
        minVersion: "TLSv1.2",
      },
    });

    // Email options
    const mailOptions = {
      from: `"BlushUp Admin" <${fromEmail}>`,
      to: email,
      subject: emailSubject,
      html: emailBody,
    };

    try {
      console.log("📤 Sending status email...");
      const info = await transporter.sendMail(mailOptions);
      console.log(`✅ Status email sent successfully!`);
      console.log(`   Message ID: ${info.messageId}`);
      console.log(`   To: ${email}`);
      console.log(`   Status: ${status}`);
      console.log("============================================");

      return {
        success: true,
        messageId: info.messageId,
        status: status,
      };
    } catch (error) {
      console.error("============================================");
      console.error("❌ SMTP ERROR:");
      console.error("   Message:", error.message);
      console.error("   Code:", error.code);
      console.error("============================================");

      throw new HttpsError(
        "internal",
        `Failed to send status email: ${error.message}`,
      );
    }
  },
);
const functions = require("firebase-functions");

const db = admin.firestore();

// ═══════════════════════════════════════════════════════════════
// TEST 1: Search Makeup Artists (Objective 1)
// ═══════════════════════════════════════════════════════════════
exports.searchArtists = onRequest(
  {region: "asia-southeast1"},
  async (req, res) => {
    try {
      const startTime = Date.now();
      const {category, location} = req.query;

      console.log("🔍 Search Request:", {category, location});

      // Build query
      let query = admin.firestore()
        .collection("makeup_artists")
        .where("status", "==", "Approved");

      // Add category filter if provided
      if (category) {
        query = query.where("category", "array-contains", category);
      }

      const snapshot = await query.get();

      // Filter by location if provided
      let artists = snapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));

      if (location) {
        artists = artists.filter((artist) =>
          artist.address &&
          artist.address.toLowerCase()
            .includes(location.toLowerCase()),
        );
      }

      const responseTime = Date.now() - startTime;

      res.status(200).json({
        success: true,
        count: artists.length,
        responseTime: responseTime,
        artists: artists,
        query: {category, location},
      });
    } catch (error) {
      console.error("❌ Search Error:", error);
      res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

// ═══════════════════════════════════════════════════════════════
// TEST 2: Get Recommendations (Objective 2)
// ═══════════════════════════════════════════════════════════════
exports.recommendArtists = functions.https.onRequest(async (req, res) => {
  const userId = req.query.userId;
  if (!userId) {
    return res.status(400).json({error: "Missing userId"});
  }

  try {
    console.log(`🔍 Recommending for user: ${userId}`);

    // STEP 1: Get Appointments (Completed + In Progress)
    const appointmentsSnap = await db.collection("appointments")
      .where("customerId", "==", db.doc(`users/${userId}`))
      .where("status", "in", ["Completed", "In Progress"])
      .get();

    const bookedArtistIds = new Set();
    const userProfile = {};
    const ratingThreshold = 3.0;

    console.log(`📋 Found ${appointmentsSnap.docs.length} appointments`);

    for (const doc of appointmentsSnap.docs) {
      const data = doc.data();
      const artistRef = data.artist_id;
      const category = data.category?.toLowerCase().trim();
      const status = data.status;

      if (!artistRef || !category) continue;

      bookedArtistIds.add(artistRef.id);

      if (!userProfile[category]) userProfile[category] = 0;

      if (status === "Completed") {
        const reviewsSnap = await db.collection("reviews")
          .where("appointment_id", "==", db.doc(`appointments/${doc.id}`))
          .get();

        let avgRating = 0;
        let total = 0;

        reviewsSnap.forEach((r) => {
          const rating = r.data().rating;
          if (rating && rating > 0) {
            avgRating += rating;
            total++;
          }
        });

        avgRating = total > 0 ? avgRating / total : 0;

        // FORMULA: Add 1 (count) if rating > threshold
        if (avgRating > ratingThreshold) {
          userProfile[category] += 1; // Add 1 instead of avgRating
          console.log(
            `✅ ${category} += 1 (rating ${avgRating.toFixed(1)} > τ)`,
          );
        } else if (avgRating > 0) {
          console.log(
            `❌ ${category} not added (rating ${avgRating.toFixed(1)} ≤ τ)`,
          );
        } else {
          // No review but completed
          userProfile[category] += 1; // Add 1 instead of 3.5
          console.log(
            `ℹ️ ${category} += 1 (no review, implicit interest)`,
          );
        }
      } else if (status === "In Progress") {
        userProfile[category] += 1; // Changed: Add 1 instead of 3.0
        console.log(`🕐 ${category} += 1 (In Progress)`);
      }
    }

    console.log(`👤 User Profile (feature counts):`, userProfile);

    // STEP 2: Get All Artists
    const allArtistsSnap = await db.collection("makeup_artists")
      .where("status", "==", "Approved")
      .get();

    const artists = [];
    const allFeatures = new Set();

    for (const doc of allArtistsSnap.docs) {
      const data = doc.data();

      // Get user_id reference
      const userIdRef = data.user_id;
      const userId = userIdRef ? userIdRef.id : null;

      // Handle categories (could be array or single field)
      let categories = [];
      if (Array.isArray(data.category)) {
        categories = data.category;
      } else if (data.category) {
        categories = [data.category];
      }

      categories.forEach((cat) => allFeatures.add(cat.toLowerCase().trim()));

      artists.push({
        id: doc.id,
        user_id: userId,
        name: data.studio_name || data.name || "Unknown Artist",
        categories: categories.map((cat) => cat.toLowerCase().trim()),
        ...data,
      });
    }

    console.log(`🎨 Found ${artists.length} approved artists`);

    // STEP 3: If no profile, fallback to preferences
    if (Object.keys(userProfile).length === 0) {
      console.log(`⚠️ No booking history, checking preferences...`);

      const userDoc = await db.collection("users").doc(userId).get();
      const preferences = userDoc.data()?.preferences || [];

      preferences.forEach((pref) => {
        const key = pref.toLowerCase().trim();
        userProfile[key] = 1; // Changed: Use 1 instead of 4.0
      });

      console.log(`👤 User Profile from preferences:`, userProfile);
    }

    // STEP 4: If still no profile, return top-rated
    if (Object.keys(userProfile).length === 0) {
      console.log(`⭐ No profile, returning top-rated artists`);

      const topRated = artists
        .map((a) => ({
          id: a.id,
          user_id: a.user_id,
          name: a.name,
          categories: a.categories,
          similarity_score: a.average_rating || 0,
          matching_features: [],
          explanation:
          `Top-rated artist (${(a.average_rating || 0).toFixed(1)}⭐)`,
        }))
        .sort((a, b) => b.similarity_score - a.similarity_score)
        .slice(0, 5);

      return res.status(200).json({
        userId,
        totalFound: topRated.length,
        recommendations: topRated,
        source: "top_rated",
      });
    }

    // STEP 5: Content-based similarity calculation
    console.log(`📊 Calculating similarity scores...`);
    const recommendations = [];

    for (const artist of artists) {
      // Skip already booked artists
      if (bookedArtistIds.has(artist.user_id)) {
        console.log(`⏭️ Skipping booked artist: ${artist.name}`);
        continue;
      }

      // Calculate similarity
      let score = 0;
      const matches = [];

      for (const category of artist.categories) {
        if (userProfile[category]) {
          score += userProfile[category]; // Sum the counts
          matches.push(category);
        }
      }

      if (score > 0) {
        console.log(`🎯 ${artist.name}: score=${score},
         matches=[${matches.join(", ")}]`);

        recommendations.push({
          id: artist.id,
          user_id: artist.user_id,
          name: artist.name,
          categories: artist.categories,
          similarity_score: score,
          matching_features: matches,
        });
      }
    }

    // STEP 6: Sort and return top 5
    recommendations.sort((a, b) => b.similarity_score - a.similarity_score);

    console.log(
      `🎊 Top ${Math.min(5, recommendations.length)} recommendations:`,
    );
    recommendations.slice(0, 5).forEach((r, i) => {
      console.log(
        `${i + 1}. ${r.name} - Score: ${r.similarity_score}`,
      );
    });

    return res.status(200).json({
      userId,
      totalFound: recommendations.length,
      recommendations: recommendations.slice(0, 5),
      source: "content_based",
      userProfile, // Include for debugging
    });
  } catch (e) {
    console.error("❌ Error in recommendArtists:", e);
    return res.status(500).json({error: e.message});
  }
});

// ═══════════════════════════════════════════════════════════════
// TEST 3: Create Booking (Objective 1)
// ═══════════════════════════════════════════════════════════════
exports.createBooking = onRequest(
  {region: "asia-southeast1"},
  async (req, res) => {
    try {
      const startTime = Date.now();
      // Use camelCase for JavaScript variables
      const {userId, artistUserId, category, date, timeRange, remarks} =
        req.body;

      console.log("📝 Received timeRange:", JSON.stringify(timeRange));

      // Validation
      if (!userId || !artistUserId || !category || !date || !timeRange) {
        return res.status(400).json({
          success: false,
          error: "Missing required fields",
        });
      }

      // Validate timeRange format
      // Supports: "9:00 AM - 12:00 PM" or "9.00 AM - 12.00 PM"
      const timeRangePattern = new RegExp(
        "^\\d{1,2}[:.]\\s?\\d{2}\\s*(AM|PM|am|pm)\\s*-\\s*" +
        "\\d{1,2}[:.]\\s?\\d{2}\\s*(AM|PM|am|pm)$",
      );

      if (!timeRangePattern.test(timeRange)) {
        return res.status(400).json({
          success: false,
          error: "Invalid time format. Use: '9:00 AM - 12:00 PM'",
        });
      }

      console.log("📅 Booking Request:", {
        userId,
        artistUserId,
        category,
        date,
        timeRange,
      });

      // Check if date is at least 3 days from now
      const bookingDate = new Date(date);
      const minDate = new Date();
      minDate.setDate(minDate.getDate() + 3);

      if (bookingDate < minDate) {
        return res.status(400).json({
          success: false,
          error: "Appointments must be booked at least 3 days in advance",
        });
      }

      // Get artist document
      const userRef = admin.firestore().doc(`users/${artistUserId}`);
      const artistSnapshot = await admin.firestore()
        .collection("makeup_artists")
        .where("user_id", "==", userRef)
        .limit(1)
        .get();

      if (artistSnapshot.empty) {
        return res.status(404).json({
          success: false,
          error: "Makeup artist not found",
        });
      }

      const artistDoc = artistSnapshot.docs[0];
      const artistData = artistDoc.data();
      const artistDocRef = artistDoc.ref;

      // Get slot configuration
      const personPerSlot = artistData["time slot"]?.person || 1;

      // Normalize timeRange for consistent comparison
      const normalizedTimeRange = timeRange
        .toUpperCase()
        .replace(/\./g, ":")
        .replace(/\s+/g, " ")
        .trim();

      // Check availability
      const existingBookings = await admin.firestore()
        .collection("appointments")
        .where("artist_id", "==", artistDocRef)
        .where("date", "==", date)
        .where("status", "in",
          ["Confirmed", "In Progress", "Completed"])
        .get();

      // Count bookings with matching timeRange
      const matchingBookings = existingBookings.docs.filter((doc) => {
        const docData = doc.data();
        const bookingTime = (docData.time_range || "")
          .toUpperCase()
          .replace(/\./g, ":")
          .replace(/\s+/g, " ")
          .trim();
        return bookingTime === normalizedTimeRange;
      });

      if (matchingBookings.length >= personPerSlot) {
        return res.status(409).json({
          success: false,
          error: "This time slot is fully booked",
        });
      }

      // Create booking
      const customerRef = admin.firestore().doc(`users/${userId}`);
      const appointmentData = {
        artist_id: artistDocRef,
        customerId: customerRef,
        category: category,
        date: date,
        time_range: normalizedTimeRange, // Firestore uses snake_case
        remarks: remarks || "None",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        status: "In Progress",
      };

      const appointmentRef = await admin.firestore()
        .collection("appointments")
        .add(appointmentData);

      const responseTime = Date.now() - startTime;

      res.status(200).json({
        success: true,
        bookingId: appointmentRef.id,
        responseTime: responseTime,
        message: "Appointment booked successfully",
        appointmentDetails: {
          date: date,
          time_range: normalizedTimeRange, // API response uses snake_case
          category: category,
        },
      });
    } catch (error) {
      console.error("❌ Booking Error:", error);
      res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

// ═══════════════════════════════════════════════════════════════
// TEST 4: Get Artist Profile (Additional test)
// ═══════════════════════════════════════════════════════════════
exports.getArtistProfile = onRequest(
  {region: "asia-southeast1"},
  async (req, res) => {
    try {
      const startTime = Date.now();
      const {artistId} = req.query;

      if (!artistId) {
        return res.status(400).json({
          success: false,
          error: "artistId is required",
        });
      }

      const artistDoc = await admin.firestore()
        .collection("makeup_artists")
        .doc(artistId)
        .get();

      if (!artistDoc.exists) {
        return res.status(404).json({
          success: false,
          error: "Artist not found",
        });
      }

      const artistData = artistDoc.data();

      // Get average rating
      const reviewsSnapshot = await admin.firestore()
        .collection("reviews")
        .where("artist_id", "==", artistDoc.ref)
        .get();

      let totalRating = 0;
      let reviewCount = 0;

      reviewsSnapshot.forEach((doc) => {
        const review = doc.data();
        if (review.rating) {
          totalRating += review.rating;
          reviewCount++;
        }
      });

      const averageRating = reviewCount > 0 ?
        totalRating / reviewCount : 0;
      const responseTime = Date.now() - startTime;

      res.status(200).json({
        success: true,
        responseTime: responseTime,
        artist: {
          id: artistDoc.id,
          ...artistData,
          average_rating: averageRating,
          total_reviews: reviewCount,
        },
      });
    } catch (error) {
      console.error("❌ Get Artist Error:", error);
      res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  },
);
