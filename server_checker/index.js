require('dotenv').config();
const http = require('http');
const axios = require('axios');
const admin = require('firebase-admin');

// 1. Initialize Firebase Admin SDK
const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!serviceAccountJson) {
  console.error("ERROR: Environment variable FIREBASE_SERVICE_ACCOUNT_JSON is missing!");
  process.exit(1);
}

try {
  const serviceAccount = JSON.parse(serviceAccountJson);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  console.log("Firebase Admin SDK initialized successfully.");
} catch (e) {
  console.error("ERROR: Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:", e.message);
  process.exit(1);
}

const db = admin.firestore();
const TELEGRAM_BOT_TOKEN = '8655291561:AAHksFJvgl0hkEnVRhD2JVDu6bJ54wmaZPY';

// 2. Helper to send Telegram messages
async function sendTelegramMessage(chatId, text) {
  if (!chatId) return;
  try {
    await axios.post(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      chat_id: chatId,
      text: text,
      parse_mode: 'HTML'
    });
    console.log(`Telegram notification sent to Chat ID ${chatId}`);
  } catch (e) {
    console.error(`Failed to send Telegram message to ${chatId}:`, e.message);
  }
}

// 3. Verification Checker function
async function checkProfileVerification(accountType, usernameOrUid) {
  try {
    let url = '';
    if (accountType.toLowerCase() === 'instagram') {
      const cleanUsername = usernameOrUid.startsWith('@') 
        ? usernameOrUid.substring(1).trim() 
        : usernameOrUid.trim();
      url = `https://www.instagram.com/${cleanUsername}/`;
    } else {
      url = `https://www.facebook.com/${usernameOrUid.trim()}/`;
    }

    const response = await axios.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
      },
      timeout: 10000,
      validateStatus: (status) => status < 500
    });

    const html = response.data || '';

    // Regex checks
    const isVerifiedRegex = /"is_verified"\s*:\s*true/;
    const verifiedRegex = /"verified"\s*:\s*true/;

    if (isVerifiedRegex.test(html) || verifiedRegex.test(html)) {
      return true;
    }

    if (accountType.toLowerCase() === 'facebook') {
      if (html.includes('verification_status') && html.includes('blue_verified')) {
        return true;
      }
    }

    return false;
  } catch (e) {
    console.error(`Error requesting profile page for ${usernameOrUid}:`, e.message);
    return false;
  }
}

// 4. Sweeper function to scan all unverified requests
async function scanUnverifiedRequests() {
  console.log(`[${new Date().toISOString()}] Starting verification sweep...`);
  try {
    const snapshot = await db.collection('requests')
      .where('isVerified', '==', false)
      .where('status', '!=', 'cancelled')
      .get();

    if (snapshot.empty) {
      console.log("No unverified requests to sweep.");
      return;
    }

    console.log(`Found ${snapshot.size} unverified requests to check.`);

    for (const doc of snapshot.docs) {
      const req = doc.data();
      console.log(`Checking ${req.accountType} account: ${req.instagramUsername}...`);

      const isNowVerified = await checkProfileVerification(req.accountType, req.instagramUsername);

      if (isNowVerified) {
        console.log(`🎉 SUCCESS: ${req.instagramUsername} has been verified!`);
        
        // Update request in Firestore
        await doc.ref.update({
          isVerified: true,
          lastAction: 'updated_verified',
          updatedAt: new Date().toISOString()
        });

        // Fetch users to notify
        const senderSnap = await db.collection('users').doc(req.senderId).get();
        const receiverSnap = await db.collection('users').doc(req.receiverId).get();

        const sender = senderSnap.exists ? senderSnap.data() : null;
        const receiver = receiverSnap.exists ? receiverSnap.data() : null;

        const serviceLabel = req.accountType === 'instagram' ? 'Instagram' : 'Facebook';
        const textMsg = `🎉 <b>TÀI KHOẢN ĐẠT TÍCH XANH!</b> 🎉\n` +
          `Tài khoản ${serviceLabel} <code>${req.instagramUsername}</code> vừa được hệ thống phát hiện đã có <b>TÍCH XANH (Verified Badge)</b> thành công!`;

        if (sender && sender.telegramChatId) {
          await sendTelegramMessage(sender.telegramChatId, textMsg);
        }
        if (receiver && receiver.telegramChatId && receiver.telegramChatId !== sender?.telegramChatId) {
          await sendTelegramMessage(receiver.telegramChatId, textMsg);
        }
      }

      // Delay 2 seconds between checks to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  } catch (e) {
    console.error("Error during sweep execution:", e.message);
  }
}

// 5. Schedule sweep every 5 minutes
const INTERVAL_MS = 5 * 60 * 1000;
setInterval(scanUnverifiedRequests, INTERVAL_MS);

// Run initial scan immediately on startup
setTimeout(scanUnverifiedRequests, 5000);

// 6. Simple HTTP Server for Health Checks (Required by Render/Koyeb)
const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  if (req.url === '/healthz' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'OK', message: 'IGCheck background service is running.' }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(PORT, () => {
  console.log(`Health check HTTP server is listening on port ${PORT}`);
});
