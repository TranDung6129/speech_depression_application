# Nhật ký giọng nói — app bệnh nhân (WP2)

Bản demo Flutter cho luồng bệnh nhân của dự án *Scoring Depression from Speech Signals*.
Dashboard bác sĩ nằm ở phía web, dùng chung backend JSON API với app này.

## Chạy thử

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` là địa chỉ máy host nhìn từ Android emulator. Máy thật cần địa chỉ
LAN hoặc domain. Backend phải đang chạy — xem `../backend/README.md`.

Yêu cầu Flutter SDK ≥ 3.19 (Dart ≥ 3.3).

## Quyền cần khai báo

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Đặt `minSdkVersion 23` trong `android/app/build.gradle`.

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Ứng dụng cần micro để ghi lại nhật ký giọng nói của bạn.</string>
```

## Cấu trúc

```
lib/
├── main.dart                     điểm vào, nạp locale tiếng Việt
├── theme/app_theme.dart          hai bảng màu: ấm (nhật ký) / mát (đánh giá)
├── models/models.dart            entry, session, câu hỏi, nhãn tự khai
├── config.dart                   base URL, tham số thử lại
├── services/
│   ├── recorder_service.dart     thu 16kHz mono WAV + kiểm tra kỹ thuật
│   ├── storage_service.dart      lưu cục bộ, draft, cài đặt
│   ├── auth_service.dart         token trong secure storage
│   └── upload_queue.dart         hàng đợi tải lên, bền qua khởi động lại
├── widgets/recording_visuals.dart vòng thở, waveform, lịch
└── screens/
    ├── sign_in_screen.dart       đăng nhập / tạo tài khoản
    ├── home_screen.dart          trang chủ + điều hướng
    ├── journal_screen.dart       nhật ký hằng ngày
    ├── assessment_screen.dart    đánh giá chuyên sâu
    ├── history_screen.dart       lịch sử và lịch tháng
    └── profile_screen.dart       hồ sơ và cài đặt
```

## Những quyết định đã mã hoá trong code

Các điểm dưới đây không phải lựa chọn thẩm mỹ — chúng ảnh hưởng trực tiếp
đến chất lượng dữ liệu, nên đừng sửa nếu chưa cân nhắc kỹ.

**Thu âm 16 kHz mono WAV, tắt xử lý của hệ điều hành.**
`echoCancel`, `noiseSuppress`, `autoGain` đều đặt `false` trong
`recorder_service.dart`. Các bộ xử lý này thay đổi biên độ và khoảng lặng —
tức là làm méo chính những đặc trưng cần đo.

**Không có nút "nghe lại rồi ghi lại".**
Chỉ có kiểm tra kỹ thuật tự động (quá ngắn, quá nhỏ, không có tín hiệu).
Cho phép ghi lại vì "không ưng nội dung" sẽ khiến bản ghi cuối cùng bớt
ngập ngừng, bớt khoảng lặng — không phải vì tâm trạng khác, mà vì người
nói đã quen câu trả lời.

**Kết thúc bằng nút bấm thủ công, không dùng VAD.**
VAD endpointing tiêu chuẩn (~700 ms im lặng) sẽ *tiêu thụ* khoảng lặng làm
tín hiệu cắt, trong khi ở đây khoảng lặng chính là thứ cần đo.

**Bệnh nhân không thấy điểm.**
`ApiClient` vẫn nhận trường điểm để đồng bộ, nhưng không màn hình nào hiển thị.
Lịch tháng chỉ có hai trạng thái đã ghi / chưa ghi, không tô màu theo cảm xúc.

**Nhãn cảm xúc là self-report, tách khỏi đầu ra mô hình.**
`MoodTag` do người dùng tự chọn từ danh sách cố định (dễ mã hoá thành biến
phân loại). Đây là nguồn dữ liệu độc lập để đối chiếu, không phải kết quả dự đoán.

**Timestamp lưu đầy đủ, không làm tròn.**
Tần suất trong phần cài đặt chỉ điều khiển lời nhắc. Khoảng cách thực tế giữa
các phiên phải đọc từ `recorded_at` / `started_at`, vì người dùng thường
không làm đúng lịch đã đặt.

**Draft bị bỏ dở không bị xoá.**
Chọn "Bắt đầu đánh giá mới" sẽ chuyển phiên cũ sang trạng thái `abandoned`
và giữ lại. Hai, ba câu đã trả lời vẫn là mẫu giọng hợp lệ.

**Hàng đợi tải lên, không gọi API trực tiếp.**
Người dùng thường ghi nhật ký ở nơi sóng yếu, và mất bản ghi vì rớt mạng là
mất dữ liệu không tái tạo được. `UploadQueue` lưu việc chờ xuống đĩa, tồn tại
qua lần khởi động app, tự chạy lại khi có mạng trở lại, và **chỉ xoá file
cục bộ sau khi máy chủ xác nhận**.

Ba nhánh xử lý lỗi khác nhau, không gộp làm một:
- Lỗi mạng hoặc 5xx → thử lại với backoff luỹ thừa (2s, 4s, 8s... tối đa 6 lần)
- 401 → token hết hạn, đăng xuất luôn thay vì đốt hết lượt thử lại
- 4xx khác (sai sample rate, file quá lớn) → dừng hẳn, vì thử lại cho kết quả y hệt

**Nhãn cảm xúc gửi kèm ngay trong lần tải lên.**
Id cục bộ và id máy chủ là hai thứ khác nhau, nên đồng bộ ngược sẽ cần thêm
bảng ánh xạ id cho đúng một trường. Thay vào đó, người dùng chọn nhãn trước,
rồi cả bản ghi lẫn nhãn đi cùng một request.

## Còn thiếu để lên bản thật

- Onboarding (hiện vào thẳng màn đăng nhập)
- Lịch nhắc thật (`flutter_local_notifications`)
- Chuyển lưu trữ từ `shared_preferences` sang sqflite/Isar
- Mã hoá file âm thanh trên thiết bị
