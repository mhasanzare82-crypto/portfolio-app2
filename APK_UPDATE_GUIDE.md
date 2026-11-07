# انتشار و به‌روزرسانی خودکار APK

## رفتار به‌روزرسانی
- برنامه هنگام بازشدن صفحه اصلی، فایل `latest.json` را از شاخه `main` می‌خواند.
- اگر `versionCode` منتشرشده از نسخه نصب‌شده بیشتر باشد، پیام دریافت نسخه جدید نمایش داده می‌شود.
- پس از تأیید کاربر، APK از `apkUrl` دانلود و نصب‌کننده رسمی Android باز می‌شود.
- اندروید برای نصب نهایی و نیز اجازه نصب از این منبع، تأیید کاربر را لازم دارد؛ نصب بی‌صدای APK در اپ معمولی مجاز نیست.
- اطلاعات SQLite و SharedPreferences با نصب به‌روزرسانی دارای package و امضای یکسان حفظ می‌شوند. تغییرات ساختار دیتابیس باید با migration سازگار انجام شوند.

## هویت برنامه و امضا
شناسه برنامه فعلاً عمداً روی `com.example.helloworld` ثابت نگه داشته شده تا با نصب‌های قبلی همین پروژه متفاوت نشود. آن را تغییر ندهید، مگر اینکه بخواهید برنامه جداگانه‌ای بسازید.

**مهم:** هر APK جدید باید با همان گواهی امضایی ساخته شود که APK نصب‌شده فعلی دارد. تغییر از debug key به release key می‌تواند به‌روزرسانی روی نصب فعلی را غیرممکن کند. قبل از انتشار عمومی، گواهی APK فعلی را بررسی و کلید سازگار را امن نگهداری کنید. فایل کلید و رمزها را در Git ثبت نکنید.

برای ساخت کلید انتشار (فقط اگر با گواهی نصب فعلی سازگار است):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

کپی `android/key.properties.example` به `android/key.properties` و تنظیم مسیر و رمزها لازم است. فایل keystore را در محل امن و خارج از مخزن نگهداری و پشتیبان‌گیری کنید.

ساخت APK:

```bash
flutter pub get
flutter build apk --release
```

خروجی معمولاً در `build/app/outputs/flutter-apk/app-release.apk` قرار می‌گیرد.

## انتشار نسخه بعدی
1. در `pubspec.yaml` نسخه را افزایش دهید؛ مثلاً `1.0.2+3`. عدد بعد از + همان `versionCode` است و باید همیشه بزرگ‌تر از نسخه قبلی باشد.
2. APK امضاشده را بسازید.
3. در GitHub یک Release بسازید و APK را دقیقاً با نام `app-release.apk` به آن پیوست کنید.
4. فایل `latest.json` در شاخه `main` را به‌روزرسانی کنید، برای نمونه:

```json
{
  "versionName": "1.0.2",
  "versionCode": 3,
  "apkUrl": "https://github.com/mhasanzare82-crypto/portfolio-app2/releases/latest/download/app-release.apk",
  "releaseNotes": "شرح تغییرات"
}
```

فایل مانیفست و Release باید پس از انتشار APK در دسترس باشند. لینک بالا به آخرین GitHub Release و asset با نام دقیق `app-release.apk` اشاره می‌کند.
