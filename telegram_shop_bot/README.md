# 🤖 Telegram Auto-Delivery Shop Bot (Bot Bán Tài Khoản FB & IG Tự Động)

Dự án này là mã nguồn Bot Telegram bán hàng tự động cho các loại tài khoản (Facebook Meta Verified, Instagram Meta Verified, Clone FB...), hỗ trợ:
- Giao diện Menu Inline Keyboards nút bấm đẹp mắt (giống 100% hình ảnh yêu cầu).
- Tự động trừ tiền số dư & xuất tài khoản từ kho.
- Tự động tạo QR chuyển khoản ngân hàng (VietQR).
- Lưu trữ SQLite siêu nhẹ, không cần cài đặt database phức tạp.
- Các lệnh Admin để nạp tài khoản vào kho (`/addstock`) và cộng tiền cho khách (`/addmoney`).

---

## 🛠️ HƯỚNG DẪN CÀI ĐẶT & CHẠY BOT

### Bước 1: Cài đặt thư viện
Mở Terminal / Command Prompt tại thư mục `telegram_shop_bot` và chạy:
```bash
npm install
```

### Bước 2: Cấu hình File `.env`
Tạo file `.env` (hoặc đổi tên từ `.env.example`) và điền thông tin:
```env
BOT_TOKEN=MÃ_TOKEN_LẤY_TỪ_BOTFATHER
ADMIN_ID=ID_TELEGRAM_CỦA_BẠN
BANK_ID=MB
ACCOUNT_NO=STK_NGÂN_HÀNG
ACCOUNT_NAME=TEN_CHU_TAI_KHOAN
```

### Bước 3: Khởi chạy Bot
```bash
npm start
```

---

## 👑 CÁC LỆNH ADMIN (QUẢN TRỊ)

Chỉ có tài khoản Telegram trùng với `ADMIN_ID` mới dùng được các lệnh này:

1. **Nhập kho tài khoản (`/addstock`):**
   Gửi lệnh theo định dạng:
   ```text
   /addstock fb_verified_vn
   61590078762827|Pass1234|2FAKEY1|cookie1
   61590078762828|Pass1234|2FAKEY2|cookie2
   ```
   *(Các mã sản phẩm có sẵn: `fb_verified_vn`, `fb_verified_ngoai`, `ig_verified_vn`, `ig_verified_ngoai`, `fb_clone_500`, `fb_clone_co`)*

2. **Cộng tiền cho khách (`/addmoney`):**
   ```text
   /addmoney <telegram_id> <số_tiền>
   Ví dụ: /addmoney 1710308922 500000
   ```

3. **Xem thống kê hệ thống (`/stats`):**
   ```text
   /stats
   ```
