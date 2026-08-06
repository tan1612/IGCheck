require('dotenv').config();
const { Telegraf, Markup } = require('telegraf');
const db = require('./database');

const BOT_TOKEN = process.env.BOT_TOKEN || 'YOUR_BOT_TOKEN_HERE';
const ADMIN_ID = process.env.ADMIN_ID || '';
const BANK_ID = process.env.BANK_ID || 'MB';
const ACCOUNT_NO = process.env.ACCOUNT_NO || '0000000000';
const ACCOUNT_NAME = process.env.ACCOUNT_NAME || 'NGUYEN VAN A';

if (!process.env.BOT_TOKEN || process.env.BOT_TOKEN === 'YOUR_BOT_TOKEN_HERE') {
  console.log('⚠️ CHÚ Ý: Chưa cấu hình BOT_TOKEN trong file .env! Vui lòng cập nhật .env để bot hoạt động.');
}

const bot = new Telegraf(BOT_TOKEN);

// Main Menu Text & Markup
function getMainText(user) {
  return (
    `🤖 *HỆ THỐNG BÁN TÀI KHOẢN TỰ ĐỘNG*\n` +
    `──────────────────────────────\n` +
    `👋 Chào mừng *${user.name}*!\n` +
    `🆔 ID Telegram: \`${user.telegram_id}\`\n` +
    `💰 Số dư hiện tại: *${user.balance.toLocaleString('vi-VN')} VNĐ*\n\n` +
    `Vui lòng chọn danh mục tính năng bên dưới:`
  );
}

function getMainMenuKeyboard() {
  return Markup.inlineKeyboard([
    [Markup.button.callback('🛒 DANH MỤC DỊCH VỤ', 'cat_menu')],
    [Markup.button.callback('💳 Nạp tiền tài khoản', 'deposit_info'), Markup.button.callback('👤 Tài khoản', 'profile_info')],
    [Markup.button.callback('📦 Lịch sử đơn hàng', 'orders_history')]
  ]);
}

// Start command
bot.start((ctx) => {
  const user = db.getOrCreateUser(ctx.from.id, ctx.from.first_name, ctx.from.username);
  return ctx.replyWithMarkdown(getMainText(user), getMainMenuKeyboard());
});

bot.command(['menu', 'help'], (ctx) => {
  const user = db.getOrCreateUser(ctx.from.id, ctx.from.first_name, ctx.from.username);
  return ctx.replyWithMarkdown(getMainText(user), getMainMenuKeyboard());
});

// Category Menu (Matching exact screenshot layout)
bot.action('cat_menu', (ctx) => {
  ctx.answerCbQuery();
  const categories = db.getCategories();
  
  const buttons = categories.map(cat => [
    Markup.button.callback(`${cat.icon} ${cat.name}`, `view_cat_${cat.id}`)
  ]);
  buttons.push([Markup.button.callback('⬅️ Quay lại', 'menu_main')]);

  const text = `🛒 *DANH MỤC DỊCH VỤ*\n──────────────────────────────\nVui lòng chọn danh mục sản phẩm bạn muốn mua:`;

  return ctx.editMessageText(text, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard(buttons)
  });
});

// Back to Main Menu
bot.action('menu_main', (ctx) => {
  ctx.answerCbQuery();
  const user = db.getOrCreateUser(ctx.from.id, ctx.from.first_name, ctx.from.username);
  return ctx.editMessageText(getMainText(user), {
    parse_mode: 'Markdown',
    ...getMainMenuKeyboard()
  });
});

// View Products in Category
bot.action(/^view_cat_(.+)$/, (ctx) => {
  ctx.answerCbQuery();
  const categoryId = ctx.match[1];
  const products = db.getProductsByCategory(categoryId);

  if (products.length === 0) {
    return ctx.editMessageText('⚠️ Hiện tại chưa có sản phẩm nào trong danh mục này.', {
      ...Markup.inlineKeyboard([[Markup.button.callback('⬅️ Quay lại', 'cat_menu')]])
    });
  }

  const buttons = products.map(prod => {
    const stock = db.getStockCount(prod.id);
    return [
      Markup.button.callback(`${prod.name} - ${prod.price.toLocaleString('vi-VN')}đ (Kho: ${stock})`, `view_prod_${prod.id}`)
    ];
  });
  buttons.push([Markup.button.callback('⬅️ Quay lại', 'cat_menu')]);

  return ctx.editMessageText(`📦 *DANH SÁCH SẢN PHẨM*\n──────────────────────────────\nChọn sản phẩm bạn cần mua:`, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard(buttons)
  });
});

// View Product Details
bot.action(/^view_prod_(.+)$/, (ctx) => {
  ctx.answerCbQuery();
  const productId = ctx.match[1];
  const product = db.getProductById(productId);
  const stock = db.getStockCount(productId);
  const user = db.getOrCreateUser(ctx.from.id);

  if (!product) return ctx.reply('Sản phẩm không tồn tại.');

  const text = (
    `📦 *CHI TIẾT SẢN PHẨM*\n` +
    `──────────────────────────────\n` +
    `📌 *Tên:* ${product.name}\n` +
    `🔑 *Mã SP:* \`${product.id}\`\n` +
    `💰 *Giá bán:* *${product.price.toLocaleString('vi-VN')} VNĐ*\n` +
    `📊 *Tồn kho:* ${stock} tài khoản\n` +
    `💳 *Số dư của bạn:* ${user.balance.toLocaleString('vi-VN')} VNĐ\n`
  );

  const buttons = [];
  if (stock > 0) {
    buttons.push([Markup.button.callback('🛒 Mua ngay (Trừ số dư)', `confirm_buy_${product.id}`)]);
  } else {
    buttons.push([Markup.button.callback('❌ Hết hàng', 'no_op')]);
  }
  buttons.push([Markup.button.callback('⬅️ Quay lại', `view_cat_${product.category_id}`)]);

  return ctx.editMessageText(text, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard(buttons)
  });
});

// Confirm Purchase
bot.action(/^confirm_buy_(.+)$/, async (ctx) => {
  ctx.answerCbQuery();
  const productId = ctx.match[1];
  
  try {
    const result = db.buyProduct(ctx.from.id, productId);

    const deliverText = (
      `🎉 *MUA HÀNG THÀNH CÔNG!*\n` +
      `──────────────────────────────\n` +
      `📦 *Sản phẩm:* ${result.productName}\n` +
      `💰 *Thành tiền:* ${result.price.toLocaleString('vi-VN')} VNĐ\n` +
      `🔑 *Thông tin tài khoản (Chép dạng Code):*\n\n` +
      `\`\`\`\n${result.accountData}\n\`\`\``
    );

    await ctx.replyWithMarkdown(deliverText);
    
    // Refresh User info and main menu
    const user = db.getOrCreateUser(ctx.from.id);
    return ctx.replyWithMarkdown(getMainText(user), getMainMenuKeyboard());
  } catch (err) {
    return ctx.reply(`❌ *Lỗi mua hàng:* ${err.message}`, { parse_mode: 'Markdown' });
  }
});

// Deposit Info (VietQR)
bot.action('deposit_info', (ctx) => {
  ctx.answerCbQuery();
  const user = db.getOrCreateUser(ctx.from.id);
  const memo = `NAP ${user.telegram_id}`;

  const qrUrl = `https://img.vietqr.io/image/${BANK_ID}-${ACCOUNT_NO}-compact2.png?amount=100000&addInfo=${encodeURIComponent(memo)}&accountName=${encodeURIComponent(ACCOUNT_NAME)}`;

  const text = (
    `💳 *NẠP TIỀN TỰ ĐỘNG BẰNG VIETQR*\n` +
    `──────────────────────────────\n` +
    `🏦 *Ngân hàng:* ${BANK_ID}\n` +
    `🔢 *Số tài khoản:* \`${ACCOUNT_NO}\`\n` +
    `👤 *Chủ tài khoản:* ${ACCOUNT_NAME}\n` +
    `📝 *Nội dung chuyển khoản (BẮT BUỘC):* \`${memo}\`\n\n` +
    `⚠️ *Lưu ý:* Vui lòng ghi ĐÚNG nội dung chuyển khoản để hệ thống tự động cộng tiền!`
  );

  return ctx.replyWithPhoto(qrUrl, {
    caption: text,
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard([[Markup.button.callback('⬅️ Quay lại Menu', 'menu_main')]])
  });
});

// Profile Info
bot.action('profile_info', (ctx) => {
  ctx.answerCbQuery();
  const user = db.getOrCreateUser(ctx.from.id, ctx.from.first_name, ctx.from.username);
  const orders = db.getUserOrders(ctx.from.id);

  const text = (
    `👤 *THÔNG TIN TÀI KHOẢN*\n` +
    `──────────────────────────────\n` +
    `📛 *Họ tên:* ${user.name}\n` +
    `🆔 *Telegram ID:* \`${user.telegram_id}\`\n` +
    `💰 *Số dư:* *${user.balance.toLocaleString('vi-VN')} VNĐ*\n` +
    `🛍️ *Tổng đơn đã mua:* ${orders.length} đơn hàng`
  );

  return ctx.editMessageText(text, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard([[Markup.button.callback('💳 Nạp tiền', 'deposit_info')], [Markup.button.callback('⬅️ Quay lại', 'menu_main')]])
  });
});

// Orders History
bot.action('orders_history', (ctx) => {
  ctx.answerCbQuery();
  const orders = db.getUserOrders(ctx.from.id);

  if (orders.length === 0) {
    return ctx.editMessageText('📦 Bạn chưa mua đơn hàng nào.', {
      ...Markup.inlineKeyboard([[Markup.button.callback('⬅️ Quay lại', 'menu_main')]])
    });
  }

  let text = `📦 *LỊCH SỬ MUA HÀNG (10 đơn gần nhất)*\n──────────────────────────────\n\n`;
  orders.forEach((ord, i) => {
    text += `*${i + 1}. ${ord.product_name}* - ${ord.price.toLocaleString('vi-VN')}đ\n`;
    text += `🔑 Dữ liệu: \`${ord.account_data}\`\n`;
    text += `🕒 Thời gian: ${ord.created_at.substring(0, 19).replace('T', ' ')}\n\n`;
  });

  return ctx.editMessageText(text, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard([[Markup.button.callback('⬅️ Quay lại', 'menu_main')]])
  });
});

// No-op for disabled buttons
bot.action('no_op', (ctx) => ctx.answerCbQuery('Sản phẩm đã hết hàng!'));

// ADMIN COMMANDS
// Add Stock: /addstock <product_id> \n <acc1> \n <acc2>
bot.command('addstock', (ctx) => {
  if (ADMIN_ID && String(ctx.from.id) !== String(ADMIN_ID)) {
    return ctx.reply('⛔ Bạn không có quyền Admin!');
  }

  const args = ctx.message.text.split('\n');
  const firstLine = args[0].split(' ');
  const productId = firstLine[1];

  if (!productId || args.length < 2) {
    return ctx.reply(
      '⚠️ *Cú pháp nhập kho hàng:* \n' +
      '`/addstock <mã_sp>`\n' +
      '`account1|pass|2fa|cookie`\n' +
      '`account2|pass|2fa|cookie`',
      { parse_mode: 'Markdown' }
    );
  }

  let count = 0;
  for (let i = 1; i < args.length; i++) {
    const line = args[i].trim();
    if (line) {
      db.addStock(productId, line);
      count++;
    }
  }

  return ctx.reply(`✅ Đã thêm thành công *${count}* tài khoản vào mã sản phẩm \`${productId}\`!`, { parse_mode: 'Markdown' });
});

// Add Money (Manual top-up): /addmoney <telegram_id> <amount>
bot.command('addmoney', (ctx) => {
  if (ADMIN_ID && String(ctx.from.id) !== String(ADMIN_ID)) {
    return ctx.reply('⛔ Bạn không có quyền Admin!');
  }

  const parts = ctx.message.text.split(' ');
  if (parts.length < 3) {
    return ctx.reply('⚠️ *Cú pháp:* `/addmoney <telegram_id> <số_tiền>`', { parse_mode: 'Markdown' });
  }

  const targetId = parts[1];
  const amount = parseInt(parts[2]);

  if (isNaN(amount)) return ctx.reply('Số tiền không hợp lệ.');

  const updatedUser = db.addBalance(targetId, amount);
  ctx.reply(`✅ Đã cộng *${amount.toLocaleString('vi-VN')} VNĐ* cho Telegram ID \`${targetId}\`. Số dư mới: *${updatedUser.balance.toLocaleString('vi-VN')} VNĐ*`, { parse_mode: 'Markdown' });

  // Notify user directly via Bot
  bot.telegram.sendMessage(
    targetId,
    `🎉 *TÀI KHOẢN ĐƯỢC CỘNG TIỀN!*\n\nSố dư của bạn vừa được cộng: *+${amount.toLocaleString('vi-VN')} VNĐ*\nSố dư hiện tại: *${updatedUser.balance.toLocaleString('vi-VN')} VNĐ*`,
    { parse_mode: 'Markdown' }
  ).catch(() => {});
});

// Admin Stats: /stats
bot.command('stats', (ctx) => {
  if (ADMIN_ID && String(ctx.from.id) !== String(ADMIN_ID)) {
    return ctx.reply('⛔ Bạn không có quyền Admin!');
  }

  const stats = db.getStats();
  const text = (
    `📊 *THỐNG KÊ BOT SHOP*\n` +
    `──────────────────────────────\n` +
    `👥 *Tổng người dùng:* ${stats.totalUsers}\n` +
    `💰 *Tổng doanh thu:* ${stats.totalSales.toLocaleString('vi-VN')} VNĐ\n` +
    `🛍️ *Tổng đơn bán ra:* ${stats.totalOrders}\n` +
    `📦 *Tài khoản chưa bán trong kho:* ${stats.inStock}`
  );

  return ctx.replyWithMarkdown(text);
});

bot.launch().then(() => {
  console.log('🚀 Telegram Shop Bot đã khởi động thành công!');
});

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
