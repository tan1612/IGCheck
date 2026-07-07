# Hướng dẫn Cài đặt & Treo Server Quét Tích Xanh 24/7 Miễn phí

Dịch vụ này được viết bằng Node.js, hoạt động ngầm độc lập 24/7 để quét các tài khoản chưa có tích xanh trên Firebase Firestore và tự động gửi thông báo về Telegram mà không phụ thuộc vào điện thoại của bạn hay đối tác (không cần mở app).

---

## BƯỚC 1: LẤY FILE CẤU HÌNH FIREBASE (SERVICE ACCOUNT JSON)

Để dịch vụ có thể đọc/ghi dữ liệu trên Firestore của bạn, bạn cần cấp quyền cho nó:

1. Truy cập **[Firebase Console](https://console.firebase.google.com/)** -> chọn dự án của bạn (`igcheck-app-5829`).
2. Nhấp vào biểu tượng **Răng cưa (Project Settings)** ở góc trên bên trái -> Chọn **Project settings**.
3. Chọn tab **Service accounts**.
4. Nhấp vào nút **Generate new private key** (Tạo khóa riêng tư mới) ở phía dưới.
5. Xác nhận và tải xuống một file dạng `.json` (Ví dụ: `igcheck-app-5829-firebase-adminsdk-xxxxx.json`).
6. Mở file JSON vừa tải bằng Notepad, sao chép toàn bộ nội dung của file này. (Chúng ta sẽ dùng nội dung này để dán vào biến môi trường ở Bước 3).

> **CẢNH BÁO BẢO MẬT:** Không bao giờ chia sẻ hoặc đẩy file JSON này lên các kho mã nguồn công khai như GitHub.

---

## BƯỚC 2: TẠO REPOSITORY TRÊN GITHUB & UP CODE

Bạn cần tải thư mục `server_checker` này lên một kho lưu trữ GitHub cá nhân (để chế độ **Private** để bảo mật):

1. Tạo một tài khoản GitHub nếu chưa có.
2. Tạo một Repository mới, đặt tên tùy ý (ví dụ: `igcheck-checker`) và đặt quyền là **Private**.
3. Đẩy toàn bộ các file trong thư mục này (`index.js`, `package.json`, `.env.example`) lên Repository đó.

---

## BƯỚC 3: TRIỂN KHAI MIỄN PHÍ TRÊN RENDER HOẶC KOYEB

Chúng ta có hai nền tảng đám mây lớn cho phép chạy Node.js 24/7 miễn phí:

### Cách A: Triển khai trên Render.com (Đơn giản nhất)
1. Đăng ký/Đăng nhập vào **[Render.com](https://render.com/)** (Bạn có thể liên kết nhanh bằng tài khoản GitHub).
2. Nhấn nút **New +** ở góc trên bên phải -> Chọn **Web Service**.
3. Liên kết tài khoản GitHub của bạn và chọn Repository `igcheck-checker` vừa tạo.
4. Thiết lập cấu hình:
   * **Name:** `igcheck-checker`
   * **Region:** Chọn vùng gần nhất (ví dụ: Singapore hoặc Oregon).
   * **Runtime:** `Node`
   * **Build Command:** `npm install`
   * **Start Command:** `npm start`
   * **Instance Type:** Chọn **Free** (Miễn phí).
5. Nhấp vào tab **Environment** bên cạnh và thêm biến môi trường sau:
   * Key: `FIREBASE_SERVICE_ACCOUNT_JSON`
   * Value: *Dán toàn bộ nội dung trong file `.json` bạn đã sao chép ở Bước 1 vào đây.*
6. Nhấn **Deploy Web Service** và đợi vài phút để hệ thống khởi chạy.

---

### Cách B: Triển khai trên Koyeb.com (Tốc độ cao hơn, không bị ngủ đông)
1. Đăng ký tài khoản trên **[Koyeb.com](https://www.koyeb.com/)**.
2. Nhấn **Create Service** -> Chọn **GitHub**.
3. Chọn Repository `igcheck-checker`.
4. Ở phần thiết lập:
   * **Builder:** Node.js
   * **Instance size:** Chọn **Nano** (vùng miễn phí của Koyeb).
   * **Ports:** Đặt cổng là `8080` (hoặc để mặc định).
5. Nhấp vào mục **Environment Variables** (Biến môi trường) và thêm:
   * Name: `FIREBASE_SERVICE_ACCOUNT_JSON`
   * Value: *Dán nội dung file `.json` của bạn vào.*
6. Nhấp **Deploy** và hệ thống sẽ tự động hoạt động độc lập 24/7.

---

## HOẠT ĐỘNG
Khi hoàn tất triển khai:
* Cứ mỗi **5 phút**, máy chủ của Render/Koyeb sẽ tự quét các tài khoản chưa lên tích xanh của bạn.
* Bạn hoàn toàn có thể tắt máy, đóng ứng dụng mà thông báo vẫn sẽ tự động gửi về Telegram khi một tài khoản thành công!
