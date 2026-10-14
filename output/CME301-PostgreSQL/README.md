# CME301 - Laboratuvar Envanter Sistemi

PostgreSQL 15 ve üzeri için hazırlanmıştır. PostgreSQL 17.11 üzerinde doğrulanmıştır.

## Hızlı kurulum (DBeaver)

1. PostgreSQL sunucunuza `postgres` veya gerekli yetkilere sahip bir hesapla bağlanın.
2. Ayrı bir SQL editöründe `CREATE DATABASE cme301_lab;` çalıştırın. Veritabanı zaten varsa bu adımı atlayın.
3. DBeaver bağlantısının **Database** alanını `cme301_lab` yapın ve yeniden bağlanın.
4. `00_install_all.sql` dosyasını açın; **Execute SQL Script / Alt+X** ile çalıştırın. Tek sorgu çalıştıran Ctrl+Enter yerine bütün betiği çalıştırın.
5. Yenileyin (F5). `Schemas > lab > Tables` altında 16 tablo görünür.
6. `05_tests.sql` dosyasını Alt+X ile çalıştırın. Sonuç: **70 PASS, 0 FAIL**. Ayrı iki oturumla eşzamanlı çıkış ve aynı lota giriş de doğrulanmıştır (`concurrency.log`). Test değişiklikleri ROLLBACK ile geri alınır.

Kurulum `lab` adında yeni bir schema oluşturur; mevcut schema veya tabloları silmez. Aynı kurulum dosyasını dolu bir `lab` schema üzerinde yeniden çalıştırmayın. Hata halinde durun; önceki başarılı bölümleri tekrar çalıştırmak yerine kalan numaralı dosyadan devam edin. `04_roles.sql` CREATEROLE yetkisi gerektirir. Önceden aynı isimle oluşturulmuş veritabanı rollerine yetki ekler.

## Dosyalar

- `01_schema.sql`: 16 tablo, 25 foreign key, indeksler ve 5 raporlama view'ı.
- `02_routines.sql`: FEFO çıkış, giriş, transfer, fire, uyarı taraması, denetim trigger'ları.
- `03_sample.sql`: sentetik örnek veri; stok ve hareket geçmişi tutarlı.
- `04_roles.sql`: Admin, Manager, Technician, Viewer yetkileri.
- `05_tests.sql`: hata kodunu da doğrulayan 70 test; test verilerini geri alır.
- `06_queries.sql`: seçim, projeksiyon, join, fark, birleşim, kesişim, bölme ve gruplama örnekleri.
- `07_demo.sql`: 8 birim FEFO çıkışı; önce 5, sonra 3 birim. Demo da ROLLBACK ile geri alınır.
- `*.log`: gerçek PostgreSQL çalıştırma ve test sonuçları.
- `diagrams/`: DBeaver diyagramları ve sunum görselleri.

## DBeaver diyagramı

`lab` schema'sını açın ve **ER Diagram** sekmesini seçin. Diyagramda tabloları gruplandırın:

- Katalog / stok: CATEGORY, ITEM, SUPPLIER, ITEM_SUPPLIER, LOT, STOCK, LOCATION, STOCK_TRANSACTION.
- Kullanıcı / denetim: ROLE, APP_USER, ALERT, AUDIT_LOG.
- Sipariş: PURCHASE_ORDER, PO_LINE.
- Cihaz: EQUIPMENT, MAINTENANCE.

Sunumda Crow's Foot gösterimini, ilişkilerde dik açılı bağlantıları ve PK/FK alanlarını kullanın. Diyagram araç çubuğundaki **Save diagram as** ile PNG dışa aktarabilirsiniz. `.erd` dosyasını farklı bilgisayarda açarken ilgili PostgreSQL bağlantısını seçin; schema adı `lab` olmalıdır.

## Tasarım kararları ve uygulama kapsamı

- ITEM alt türleri `item_type` ile tek tabloda tutulur; cihazlar ayrı EQUIPMENT tablosundadır.
- Bir lot birden çok konumda bulunabilir. STOCK anahtarı `(lot_id,location_id)` olur.
- LOT.initial_qty ilk kabul miktarıdır; toplam girişler hareket geçmişinden hesaplanır.
- SKT bütün lotlarda zorunludur; bugünün SKT'si çıkış için geçerli kabul edilir. Yeni mal kabulünde gelecek tarih istenir.
- Otomatik uyarı taraması stok prosedürleri sonunda çağrılır. İşlem olmayan günlerde de SKT değişimini yakalamak için günlük bir zamanlayıcının `CALL lab.sp_refresh_alerts();` çalıştırması gerekir. Zamanlayıcı bu pakette kurulmaz.
- Üretim GUI'sinde gerçek parola hash'i, parametrik sorgular ve oturum doğrulaması gerekir. Örnek veri hash alanları giriş için kullanılamaz.
- Veritabanı sahibi güvenilir backend olarak kabul edilir ve uygulama kullanıcısını prosedür parametresiyle aktarabilir. Diğer PostgreSQL login'leri, APP_USER.db_login alanında kendi uygulama kullanıcılarıyla eşleştirilmelidir. Uygulama oturumu ile kullanıcı eşlemesini backend yapar.
- Depolama sıcaklığı alanları vardır; sıcaklık uyumluluğu ve sipariş durum geçişleri için kapsamlı iş akışı henüz uygulanmamıştır.
- Bu teslim küçük demo veri setini ve fonksiyonel testleri kapsar; 10.000+ hareketli performans deneyi ve GUI, sonraki uygulama aşamasıdır.

## Yeniden üretim

Orijinal dosyalar değiştirilmemiştir. SQL betikleri `tools/prepare_delivery.py` ile hazırlanmıştır.

Resmî DBeaver yönergesi: https://dbeaver.com/docs/dbeaver/ER-Diagrams/
