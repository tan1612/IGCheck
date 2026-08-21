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
async function sendTelegramMessage(chatId, text, replyMarkup = null) {
  if (!chatId) return;
  try {
    const payload = {
      chat_id: chatId,
      text: text,
      parse_mode: 'HTML'
    };
    if (replyMarkup) {
      payload.reply_markup = replyMarkup;
    }
    await axios.post(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, payload);
    console.log(`Telegram message sent to Chat ID ${chatId}`);
  } catch (e) {
    console.error(`Failed to send Telegram message to ${chatId}:`, e.message);
  }
}

async function sendTelegramLongMessage(chatId, text, replyMarkup = null) {
  if (text.length <= 3500) {
    await sendTelegramMessage(chatId, text, replyMarkup);
    return;
  }
  const chunks = text.match(/[\s\S]{1,3500}/g) || [];
  for (let i = 0; i < chunks.length; i++) {
    const isLast = i === chunks.length - 1;
    await sendTelegramMessage(chatId, chunks[i], isLast ? replyMarkup : null);
    await new Promise(resolve => setTimeout(resolve, 500));
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

function withHardTimeout(promise, ms = 10000) {
  let timer;
  const timeoutPromise = new Promise((resolve) => {
    timer = setTimeout(() => {
      resolve({ isLive: null, isVerified: null, error: 'Hard timeout exceeded' });
    }, ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

// 4. Sweeper function to scan all active requests (Live/Die & Tích xanh status)
let isSweeping = false;

async function scanActiveRequests() {
  if (isSweeping) {
    console.log(`[${new Date().toISOString()}] Sweep is already in progress, skipping duplicate trigger.`);
    return;
  }
  isSweeping = true;
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
      try {
        const req = doc.data();
        const serviceLabel = req.accountType === 'facebook' ? 'Facebook' : 'Instagram';
        const username = req.instagramUsername;

        console.log(`Checking ${serviceLabel} account: ${username}...`);

        const result = await withHardTimeout(checkProfileStatus(req.accountType, username), 10000);

        // Skip if network request failed completely (e.g. timeout / internet loss)
        if (result.isLive === null) {
          await new Promise(resolve => setTimeout(resolve, 1500));
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
      } catch (errDoc) {
        console.error(`Error processing request doc ${doc.id}:`, errDoc.message);
      }

      // Delay 1.5 seconds between checks to prevent rate limiting
      await new Promise(resolve => setTimeout(resolve, 1500));
    }
  } catch (e) {
    console.error("Error during sweep execution:", e.message);
  } finally {
    isSweeping = false;
  }
}

// 5. Schedule sweep every 5 minutes
const INTERVAL_MS = 5 * 60 * 1000;
setInterval(scanActiveRequests, INTERVAL_MS);

// Run initial scan immediately on startup
setTimeout(scanActiveRequests, 5000);

// 6. Telegram Interactive Bot Menu & Polling Logic
const defaultReplyKeyboard = {
  keyboard: [
    [{ text: '💙 DS Tài khoản Tích Xanh' }, { text: '🔴 DS Tài khoản DIE' }],
    [{ text: '📋 Danh sách Tất cả Hồ sơ' }, { text: '❓ Hướng dẫn' }]
  ],
  resize_keyboard: true,
  persistent: true
};

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function handleTelegramMessage(msg) {
  const chatId = msg.chat.id;
  const text = (msg.text || '').trim();
  let textLower = text.toLowerCase().replace(/@\w+/g, '');

  console.log(`Received Telegram message from ${chatId}: "${text}"`);

  if (textLower === '/start' || textLower === '/menu' || textLower === 'menu' || textLower === '❓ hướng dẫn') {
    const welcomeMsg = `🤖 <b>HỆ THỐNG QUẢN LÝ TÀI KHOẢN TÍCH XANH & LIVE/DIE</b>\n\n` +
      `Vui lòng chọn nút chức năng bên dưới menu để xem và lấy tài khoản bán:\n\n` +
      `• <b>💙 DS Tài khoản Tích Xanh:</b> Xem & copy nhanh thông tin (User, Pass, 2FA) tài khoản đã tích xanh để bán.\n` +
      `• <b>🔴 DS Tài khoản DIE:</b> Danh sách các tài khoản bị chết/bị khóa.\n` +
      `• <b>📋 Danh sách Tất cả Hồ sơ:</b> Danh sách tổng thể toàn bộ hồ sơ.`;

    await sendTelegramMessage(chatId, welcomeMsg, defaultReplyKeyboard);
    return;
  }

  if (textLower.includes('tích xanh') || textLower === '/tichxanh') {
    try {
      const snapshot = await db.collection('requests').get();
      const verifiedDocs = snapshot.docs.filter(doc => doc.data().isVerified === true && doc.data().status !== 'cancelled');

      if (verifiedDocs.length === 0) {
        await sendTelegramMessage(chatId, `💙 <b>DS TÀI KHOẢN TÍCH XANH</b> 💙\n\nHiện chưa có tài khoản nào đạt tích xanh.`, defaultReplyKeyboard);
        return;
      }

      let message = `💙 <b>DANH SÁCH TÀI KHOẢN ĐÃ CÓ TÍCH XANH (${verifiedDocs.length} ACC)</b> 💙\n` +
        `<i>(Chạm trực tiếp vào chữ định dạng code để sao chép nhanh)</i>\n\n`;

      verifiedDocs.forEach((doc, idx) => {
        const r = doc.data();
        const typeLabel = r.accountType === 'facebook' ? 'Facebook' : 'Instagram';
        const userClean = escapeHtml(r.instagramUsername);
        const passClean = escapeHtml(r.password || 'N/A');
        const twoFaClean = escapeHtml(r.twoFactorKey || 'N/A');
        const nameClean = escapeHtml(r.displayName || 'N/A');

        message += `<b>${idx + 1}. ${typeLabel}: @${userClean}</b>\n` +
          `• Họ tên: <b>${nameClean}</b>\n` +
          `• User: <code>${userClean}</code>\n` +
          `• Pass: <code>${passClean}</code>\n` +
          `• 2FA: <code>${twoFaClean}</code>\n` +
          `• Trạng thái: 💙 <b>TÍCH XANH</b>\n\n`;
      });

      await sendTelegramLongMessage(chatId, message, defaultReplyKeyboard);
    } catch (e) {
      await sendTelegramMessage(chatId, `Lỗi khi lấy danh sách tích xanh: ${e.message}`, defaultReplyKeyboard);
    }
    return;
  }

  if (textLower.includes('die') || textLower === '/die') {
    try {
      const snapshot = await db.collection('requests').get();
      const deadDocs = snapshot.docs.filter(doc => doc.data().accountStatus === 'dead' && doc.data().status !== 'cancelled');

      if (deadDocs.length === 0) {
        await sendTelegramMessage(chatId, `🔴 <b>DS TÀI KHOẢN DIE</b> 🔴\n\nKhông có tài khoản nào bị DIE.`, defaultReplyKeyboard);
        return;
      }

      let message = `🔴 <b>DANH SÁCH TÀI KHOẢN DIE (${deadDocs.length} ACC)</b> 🔴\n\n`;

      deadDocs.forEach((doc, idx) => {
        const r = doc.data();
        const typeLabel = r.accountType === 'facebook' ? 'Facebook' : 'Instagram';
        const userClean = escapeHtml(r.instagramUsername);
        const nameClean = escapeHtml(r.displayName || 'N/A');

        message += `<b>${idx + 1}. ${typeLabel}: @${userClean}</b>\n` +
          `• Họ tên: <b>${nameClean}</b>\n` +
          `• User: <code>${userClean}</code>\n` +
          `• Trạng thái: 🔴 <b>BỊ DIE / KHÓA</b>\n\n`;
      });

      await sendTelegramLongMessage(chatId, message, defaultReplyKeyboard);
    } catch (e) {
      await sendTelegramMessage(chatId, `Lỗi khi lấy danh sách DIE: ${e.message}`, defaultReplyKeyboard);
    }
    return;
  }

  if (textLower.includes('tất cả') || textLower === '/tatca') {
    try {
      const snapshot = await db.collection('requests').get();
      const activeDocs = snapshot.docs.filter(doc => doc.data().status !== 'cancelled');

      if (activeDocs.length === 0) {
        await sendTelegramMessage(chatId, `📋 <b>DANH SÁCH HỒ SƠ</b> 📋\n\nChưa có hồ sơ nào.`, defaultReplyKeyboard);
        return;
      }

      let message = `📋 <b>DANH SÁCH TẤT CẢ HỒ SƠ (${activeDocs.length} ACC)</b> 📋\n\n`;

      activeDocs.forEach((doc, idx) => {
        const r = doc.data();
        const typeLabel = r.accountType === 'facebook' ? 'Facebook' : 'Instagram';
        const statusIcon = r.isVerified ? '💙 TÍCH XANH' : r.accountStatus === 'dead' ? '🔴 DIE' : '✅ LIVE';
        const userClean = escapeHtml(r.instagramUsername);
        const nameClean = escapeHtml(r.displayName || 'N/A');

        message += `<b>${idx + 1}. ${typeLabel}: @${userClean}</b>\n` +
          `• Họ tên: ${nameClean}\n` +
          `• Trạng thái: <b>${statusIcon}</b>\n\n`;
      });

      await sendTelegramLongMessage(chatId, message, defaultReplyKeyboard);
    } catch (e) {
      await sendTelegramMessage(chatId, `Lỗi khi lấy danh sách hồ sơ: ${e.message}`, defaultReplyKeyboard);
    }
    return;
  }
}

let lastUpdateId = 0;

async function pollTelegramUpdates() {
  try {
    const response = await axios.get(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates`, {
      params: {
        offset: lastUpdateId + 1,
        timeout: 1,
      },
      timeout: 5000,
    });

    const updates = response.data.result || [];
    for (const update of updates) {
      lastUpdateId = Math.max(lastUpdateId, update.update_id);
      try {
        if (update.message && update.message.text) {
          await handleTelegramMessage(update.message);
        }
      } catch (err) {
        console.error(`Error handling update ${update.update_id}:`, err?.message || err);
      }
    }
  }
  } catch (e) {
    const errStr = String(e?.message || e || '');
    if (!errStr.includes('timeout') && !errStr.includes('ECONNABORTED')) {
      console.error('Error polling Telegram updates:', errStr);
    }
  }
}

async function startTelegramBotPolling() {
  try {
    await axios.post(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands`, {
      commands: [
        { command: 'menu', description: 'Hiển thị menu nút bấm' },
        { command: 'tichxanh', description: 'DS tài khoản Tích Xanh (Lấy bán)' },
        { command: 'die', description: 'DS tài khoản bị DIE' },
        { command: 'tatca', description: 'DS tất cả hồ sơ' },
      ]
    });
    console.log("Telegram Bot commands registered successfully.");
  } catch (e) {
    console.error("Failed to register Telegram commands:", e?.message || e);
  }

  while (true) {
    try {
      await pollTelegramUpdates();
    } catch (err) {
      console.error("Error in Telegram bot polling loop:", err?.message || err);
    }
    await new Promise(resolve => setTimeout(resolve, 1500));
  }
}

// Start polling in background
startTelegramBotPolling();

// 7. Simple HTTP Server for Health Checks (Required by Render/Koyeb)
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

// 8. Self-ping every 4 minutes to keep Render Free Instance awake 24/7 without sleeping
const RENDER_EXTERNAL_URL = process.env.RENDER_EXTERNAL_URL || 'https://igcheck-checker.onrender.com';
setInterval(async () => {
  try {
    await axios.get(`${RENDER_EXTERNAL_URL}/healthz`, { timeout: 10000 });
    console.log("Self-ping sent to keep Render instance active.");
  } catch (e) {
    // Ignore ping errors
  }
}, 4 * 60 * 1000);

