# CME301 Laboratory Inventory System

Database Management Systems dersinin laboratuvar envanter projesi. PostgreSQL üzerinde malzeme, tedarikçi, lot, son kullanma tarihi, konum, stok hareketi, sipariş ve cihaz bakımını modelleyen bir veritabanıdır.

## Mevcut durum

- 16 tablo, 25 foreign key ve 5 raporlama view'ı.
- FEFO ile stok çıkışı; stok girişi, transfer ve fire prosedürleri.
- Denetim trigger'ları, uyarı taraması ve rol bazlı veritabanı yetkileri.
- Sentetik örnek veri, ilişkisel cebir sorguları ve geri alınabilir demo.
- PostgreSQL 17.11 üzerinde 70/70 başarılı fonksiyonel test.
- İki ayrı oturumla eşzamanlı stok çıkışı ve aynı lota giriş doğrulandı.
- Tam şema ve ana stok modeli için DBeaver `.erd` kaynakları hazır. DBeaver içinde görsel açılış kontrolü ve DBeaver PNG dışa aktarımı henüz tamamlanmadı.

## Dosya düzeni

| Yol | İçerik |
| --- | --- |
| `output/CME301-PostgreSQL/` | Çalıştırılabilir SQL teslimi, test sonuçları ve kullanım açıklaması |
| `output/CME301-PostgreSQL/diagrams/` | DBeaver `.erd` kaynakları, metadata, sadeleştirilmiş sunum görselleri |
| `sql/source/` | İlk SQL taslaklarının korunmuş kopyaları |
| `tools/` | SQL teslimi, test ve diyagram hazırlama araçları |
| `docs/ROADMAP.md` | Tamamlanan işler ve sonraki adımlar |
| `docs/LOCAL_DATABASE.md` | Yerel sunucu, bağlantı bilgileri ve DBeaver açıklaması |
| `.env.example` | Parola içermeyen bağlantı şablonu |

## Kurulum

1. PostgreSQL 15+ sunucusu ve DBeaver kullanın.
2. `.env.example` dosyasını `.env` olarak kopyalayıp kendi PostgreSQL bağlantı bilgilerinizi yazın.
3. PostgreSQL'de `cme301_lab` veritabanını oluşturup ona bağlanın.
4. `output/CME301-PostgreSQL/00_install_all.sql` dosyasını DBeaver'da **Execute SQL Script / Alt+X** ile çalıştırın. Kurulum boş bir `lab` schema bekler; mevcut tabloları silmez.
5. `05_tests.sql` dosyasını çalıştırın. Test değişiklikleri ROLLBACK ile geri alınır.
6. Tabloları DBeaver'da **Schemas > lab > Tables**, ilişkileri **ER Diagram** altında inceleyin.

Numaralı SQL dosyaları ayrı ayrı da çalıştırılabilir. Ayrıntılar: [SQL teslimi README](output/CME301-PostgreSQL/README.md).

`.env` dosyası Git'e eklenmez. Bu dosya sunucuyu kendi başına kurmaz veya parolayı değiştirmez; araçların bağlantı ayarlarını içerir. Diğer grup üyeleri kendi bilgisayarlarında PostgreSQL kurmalı ve kendi `.env` dosyalarını oluşturmalıdır.

## Bu bilgisayardaki sunucu

Proje için Windows taşınabilir PostgreSQL 17.11 dosyalarıyla ayrı bir yerel sunucu başlatıldı. Docker veya uzak bir bulut sunucusu kullanılmadı. Sunucu `127.0.0.1:54329` üzerinde dinler; veritabanı `cme301_lab`, schema `lab`, veritabanı kullanıcısı `postgres` olur.

İstenen parola Windows parolası değildir. Bu yerel PostgreSQL sunucusu için üretilen parola `.env` içinde bulunur. Parola, PostgreSQL program dosyaları ve veri klasörü public depoya gönderilmez.

Yerel sunucuyu yönetmek için:

```powershell
.\tools\manage_postgres.ps1 -Action status
.\tools\manage_postgres.ps1 -Action start
.\tools\manage_postgres.ps1 -Action stop
```

Bu komutlar proje içindeki `.local/postgres-runtime/pgsql/bin` ve `.local/postgres-data` klasörlerini kullanır. Yeni bir clone'da bu klasörler bulunmaz; normal PostgreSQL kurulumuyla SQL dosyalarını çalıştırabilirsiniz.

## Yeniden üretim

```powershell
python tools/prepare_delivery.py
```

Araç ilk taslakları `sql/source/` içinden okuyup numaralı SQL teslimini yeniden üretir. `00_install_all.sql` da aynı işlemde güncellenir. Sunum görseli için `python tools/build_schema_visual.py` kullanılabilir; bu PNG/SVG çıktısı DBeaver export'u değildir.

Günlük SKT zamanlayıcısı, 10.000+ hareketli performans deneyi ve GUI sonraki işler arasındadır. [Yol haritası](docs/ROADMAP.md) ve [yerel bağlantı rehberi](docs/LOCAL_DATABASE.md) güncel sınırları açıklar.
