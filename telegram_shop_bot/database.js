const Database = require('better-sqlite3');
const path = require('path');

const db = new Database(path.join(__dirname, 'shop.db'));

// Initialize tables
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    telegram_id TEXT PRIMARY KEY,
    name TEXT,
    username TEXT,
    balance INTEGER DEFAULT 0,
    created_at TEXT
  );

  CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    name TEXT,
    icon TEXT
  );

  CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    category_id TEXT,
    name TEXT,
    price INTEGER
  );

  CREATE TABLE IF NOT EXISTS stock (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id TEXT,
    account_data TEXT,
    is_sold INTEGER DEFAULT 0,
    created_at TEXT
  );

  CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_id TEXT,
    product_name TEXT,
    price INTEGER,
    account_data TEXT,
    created_at TEXT
  );
`);

// Insert default categories & products if empty
const catCheck = db.prepare('SELECT COUNT(*) as count FROM categories').get();
if (catCheck.count === 0) {
  const insertCat = db.prepare('INSERT INTO categories (id, name, icon) VALUES (?, ?, ?)');
  insertCat.run('fb_verified', 'Facebook Meta Verified', '✅');
  insertCat.run('ig_verified', 'Instagram Meta Verified', '📸');
  insertCat.run('fb_clone', 'Clone Facebook', '🥷');

  const insertProd = db.prepare('INSERT INTO products (id, category_id, name, price) VALUES (?, ?, ?, ?)');
  insertProd.run('fb_verified_vn', 'fb_verified', 'FB Tích Xanh Việt (Full 2FA)', 550000);
  insertProd.run('fb_verified_ngoai', 'fb_verified', 'FB Tích Xanh Ngoại (Full 2FA)', 480000);
  insertProd.run('ig_verified_vn', 'ig_verified', 'IG Tích Xanh Việt (Chính Chủ)', 600000);
  insertProd.run('ig_verified_ngoai', 'ig_verified', 'IG Tích Xanh Ngoại (Cổ + 2FA)', 520000);
  insertProd.run('fb_clone_500', 'fb_clone', 'Clone FB 500 Bạn Bè (2FA)', 15000);
  insertProd.run('fb_clone_co', 'fb_clone', 'Clone FB Cổ 2015-2020', 35000);
}

// User Helpers
function getOrCreateUser(telegramId, name, username) {
  let user = db.prepare('SELECT * FROM users WHERE telegram_id = ?').get(String(telegramId));
  if (!user) {
    db.prepare('INSERT INTO users (telegram_id, name, username, balance, created_at) VALUES (?, ?, ?, 0, ?)')
      .run(String(telegramId), name || 'Khách', username || '', new Date().toISOString());
    user = db.prepare('SELECT * FROM users WHERE telegram_id = ?').get(String(telegramId));
  }
  return user;
}

function addBalance(telegramId, amount) {
  getOrCreateUser(telegramId);
  db.prepare('UPDATE users SET balance = balance + ? WHERE telegram_id = ?').run(amount, String(telegramId));
  return db.prepare('SELECT * FROM users WHERE telegram_id = ?').get(String(telegramId));
}

function deductBalance(telegramId, amount) {
  db.prepare('UPDATE users SET balance = balance - ? WHERE telegram_id = ?').run(amount, String(telegramId));
}

// Product & Stock Helpers
function getCategories() {
  return db.prepare('SELECT * FROM categories').all();
}

function getProductsByCategory(categoryId) {
  return db.prepare('SELECT * FROM products WHERE category_id = ?').all(categoryId);
}

function getProductById(productId) {
  return db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
}

function getStockCount(productId) {
  const result = db.prepare('SELECT COUNT(*) as count FROM stock WHERE product_id = ? AND is_sold = 0').get(productId);
  return result ? result.count : 0;
}

function addStock(productId, accountData) {
  db.prepare('INSERT INTO stock (product_id, account_data, is_sold, created_at) VALUES (?, ?, 0, ?)')
    .run(productId, accountData, new Date().toISOString());
}

function buyProduct(telegramId, productId) {
  const product = getProductById(productId);
  if (!product) throw new Error('Sản phẩm không tồn tại!');

  const user = getOrCreateUser(telegramId);
  if (user.balance < product.price) {
    throw new Error(`Số dư không đủ! Cần ${product.price.toLocaleString('vi-VN')}đ, bạn hiện có ${user.balance.toLocaleString('vi-VN')}đ. Vui lòng nạp thêm tiền.`);
  }

  const stockItem = db.prepare('SELECT * FROM stock WHERE product_id = ? AND is_sold = 0 LIMIT 1').get(productId);
  if (!stockItem) {
    throw new Error('Tạm thời hết hàng! Vui lòng chọn sản phẩm khác hoặc báo Admin nạp thêm.');
  }

  // Deduct balance and mark stock as sold
  deductBalance(telegramId, product.price);
  db.prepare('UPDATE stock SET is_sold = 1 WHERE id = ?').run(stockItem.id);

  // Record order
  db.prepare('INSERT INTO orders (telegram_id, product_name, price, account_data, created_at) VALUES (?, ?, ?, ?, ?)')
    .run(String(telegramId), product.name, product.price, stockItem.account_data, new Date().toISOString());

  return {
    productName: product.name,
    price: product.price,
    accountData: stockItem.account_data
  };
}

function getUserOrders(telegramId) {
  return db.prepare('SELECT * FROM orders WHERE telegram_id = ? ORDER BY id DESC LIMIT 10').all(String(telegramId));
}

function getStats() {
  const totalUsers = db.prepare('SELECT COUNT(*) as c FROM users').get().c;
  const totalSales = db.prepare('SELECT SUM(price) as s FROM orders').get().s || 0;
  const totalOrders = db.prepare('SELECT COUNT(*) as c FROM orders').get().c;
  const inStock = db.prepare('SELECT COUNT(*) as c FROM stock WHERE is_sold = 0').get().c;

  return { totalUsers, totalSales, totalOrders, inStock };
}

module.exports = {
  db,
  getOrCreateUser,
  addBalance,
  getCategories,
  getProductsByCategory,
  getProductById,
  getStockCount,
  addStock,
  buyProduct,
  getUserOrders,
  getStats
};
