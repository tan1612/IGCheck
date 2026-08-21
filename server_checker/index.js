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

// 3. Profile Status & Verification Checker function
async function checkProfileStatus(accountType, usernameOrUid) {
  try {
    let url = '';
    const cleanUser = usernameOrUid.startsWith('@') 
      ? usernameOrUid.substring(1).trim() 
      : usernameOrUid.trim();

    if (accountType.toLowerCase() === 'instagram') {
      url = `https://www.instagram.com/${cleanUser}/`;
    } else {
      url = `https://www.facebook.com/${cleanUser}/`;
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

    const statusCode = response.status;
    const html = response.data || '';

    // Check for 404 HTTP status code
    if (statusCode === 404) {
      return { isLive: false, isVerified: false };
    }

    // Check for DEAD keywords in HTML content
    const deadKeywords = [
      'page not found',
      'trang này không hiển thị',
      'trang me không hiển thị',
      'trang này không tồn tại',
      'trang này không khả dụng',
      "this content isn't available right now",
      "this page isn't available",
      "sorry, this page isn't available",
      'the link you followed may be broken',
      'user_disabled',
      'rest_of_world_account_disabled',
      'profile_not_found'
    ];

    const htmlLower = typeof html === 'string' ? html.toLowerCase() : '';
    for (const kw of deadKeywords) {
      if (htmlLower.includes(kw)) {
        return { isLive: false, isVerified: false };
      }
    }

    // Check for VERIFIED indicators
    const isVerifiedRegex = /"is_verified"\s*:\s*true/;
    const verifiedRegex = /"verified"\s*:\s*true/;
    let isVerified = isVerifiedRegex.test(html) || verifiedRegex.test(html);

    if (accountType.toLowerCase() === 'facebook') {
      if (html.includes('verification_status') && html.includes('blue_verified')) {
        isVerified = true;
      }
    }

    return { isLive: true, isVerified };
  } catch (e) {
    console.error(`Error requesting profile page for ${usernameOrUid}:`, e.message);
    return { isLive: null, isVerified: null, error: e.message };
  }
}

// 4. Sweeper function to scan all active requests (Live/Die & Tích xanh status)
async function scanActiveRequests() {
  console.log(`[${new Date().toISOString()}] Starting status and verification sweep...`);
  try {
    const snapshot = await db.collection('requests').get();

    if (snapshot.empty) {
      console.log("No requests to sweep.");
      return;
    }

    const activeDocs = snapshot.docs.filter(doc => doc.data().status !== 'cancelled');

    if (activeDocs.length === 0) {
      console.log("No active requests to sweep.");
      return;
    }

    console.log(`Found ${activeDocs.length} active requests to check.`);

    for (const doc of activeDocs) {
      const req = doc.data();
      const serviceLabel = req.accountType === 'facebook' ? 'Facebook' : 'Instagram';
      const username = req.instagramUsername;

      console.log(`Checking ${serviceLabel} account: ${username}...`);

      const result = await checkProfileStatus(req.accountType, username);

      // Skip if network request failed completely (e.g. timeout / internet loss)
      if (result.isLive === null) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        continue;
      }

      const prevVerified = !!req.isVerified;
      const prevAccountStatus = req.accountStatus || 'unknown';

      const currentVerified = result.isVerified;
      const currentAccountStatus = result.isLive ? 'live' : 'dead';

      let updateData = {};
      let notifications = [];

      // 1. Check for NEW VERIFIED (Tích Xanh) status
      if (currentVerified && !prevVerified) {
        console.log(`🎉 SUCCESS: ${username} has achieved VERIFIED status!`);
        updateData.isVerified = true;
        notifications.push(
          `🎉 <b>TÀI KHOẢN ĐẠT TÍCH XANH!</b> 🎉\n` +
          `Tài khoản ${serviceLabel} <code>${username}</code> vừa được phát hiện đã có <b>TÍCH XANH (Verified Badge)</b> thành công!`
        );
      }

      // 2. Check for Account DIE status change
      if (currentAccountStatus === 'dead' && prevAccountStatus !== 'dead') {
        console.log(`⚠️ ALERT: ${username} is DEAD!`);
        updateData.accountStatus = 'dead';
        notifications.push(
          `⚠️ <b>CẢNH BÁO TÀI KHOẢN BỊ DIE!</b> ⚠️\n` +
          `Tài khoản ${serviceLabel} <code>${username}</code> vừa chuyển trạng thái sang <b>DIE (Bị vô hiệu hóa / Không tồn tại)</b>!`
        );
      }
      // 3. Check for Account RESTORED (DIE -> LIVE)
      else if (currentAccountStatus === 'live' && prevAccountStatus === 'dead') {
        console.log(`✅ RESTORED: ${username} is LIVE again!`);
        updateData.accountStatus = 'live';
        notifications.push(
          `✅ <b>TÀI KHOẢN ĐÃ LIVE TRỞ LẠI!</b> ✅\n` +
          `Tài khoản ${serviceLabel} <code>${username}</code> vừa khôi phục trạng thái <b>LIVE</b> hoạt động bình thường!`
        );
      }
      // 4. Initial check for newly added account if it's already dead on creation
      else if (prevAccountStatus === 'unknown' && currentAccountStatus === 'dead') {
        console.log(`⚠️ ALERT: Newly added ${username} is DEAD!`);
        updateData.accountStatus = 'dead';
        notifications.push(
          `⚠️ <b>CẢNH BÁO: TÀI KHOẢN MỚI GỬI ĐÃ BỊ DIE!</b> ⚠️\n` +
          `Tài khoản ${serviceLabel} <code>${username}</code> vừa gửi nhưng đã ở trạng thái <b>DIE</b>!`
        );
      } else if (prevAccountStatus === 'unknown') {
        updateData.accountStatus = 'live';
      }

      // Save updates to Firestore
      if (Object.keys(updateData).length > 0) {
        updateData.updatedAt = new Date().toISOString();
        if (!updateData.lastAction) {
          updateData.lastAction = updateData.isVerified ? 'updated_verified' : 'updated_account_status';
        }
        await doc.ref.update(updateData);
      }

      // Send Telegram notifications to sender & receiver
      if (notifications.length > 0) {
        const senderSnap = await db.collection('users').doc(req.senderId).get();
        const receiverSnap = await db.collection('users').doc(req.receiverId).get();

        const sender = senderSnap.exists ? senderSnap.data() : null;
        const receiver = receiverSnap.exists ? receiverSnap.data() : null;

        for (const textMsg of notifications) {
          if (sender && sender.telegramChatId) {
            await sendTelegramMessage(sender.telegramChatId, textMsg);
          }
          if (receiver && receiver.telegramChatId && receiver.telegramChatId !== sender?.telegramChatId) {
            await sendTelegramMessage(receiver.telegramChatId, textMsg);
          }
        }
      }

      // Delay 2 seconds between checks to prevent rate limiting
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  } catch (e) {
    console.error("Error during sweep execution:", e.message);
  }
}

// 5. Schedule sweep every 5 minutes
const INTERVAL_MS = 5 * 60 * 1000;
setInterval(scanActiveRequests, INTERVAL_MS);

// Run initial scan immediately on startup
setTimeout(scanActiveRequests, 5000);

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
