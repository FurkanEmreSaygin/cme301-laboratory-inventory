# Veritabanı nerede, hangi parola gerekiyor?

## Kurduğumuz şey

Bilgisayarda çalışan ayrı bir **PostgreSQL 17.11 sunucusu** kuruldu. Resmî PostgreSQL Windows dağıtımındaki EDB taşınabilir program dosyaları indirildi; `initdb` ile proje için yeni bir veri klasörü oluşturuldu ve `pg_ctl` ile sunucu başlatıldı.

Bu kurulum Windows servisi olarak kaydedilmedi. Docker ve bulut sunucusu kullanılmadı. Bilgisayar yeniden başlarsa sunucuyu yeniden başlatmak gerekir.

```text
DBeaver veya Python araçları
        |
        | 127.0.0.1:54329
        v
Bu bilgisayardaki PostgreSQL sunucusu
        |
        +-- cme301_lab veritabanı
                 |
                 +-- lab schema
                          |
                          +-- 16 tablo, view, prosedür ve trigger'lar
```

## DBeaver bağlantısı

| Alan | Değer |
| --- | --- |
| Driver | PostgreSQL |
| Host | `127.0.0.1` |
| Port | `54329` |
| Database | `cme301_lab` |
| Username | `postgres` |
| Password | Bu bilgisayardaki `.env` dosyasının `PGPASSWORD` değeri |
| Schema | `lab` |

**Windows giriş parolanı veya GitHub parolanı vermen gerekmiyor.** `postgres`, veritabanında oluşturulan yönetici hesabıdır. Bu hesaba proje kurulumunda rastgele bir veritabanı parolası üretildi.

DBeaver veritabanı sunucusu değildir; ona bağlanıp tabloları, kayıtları, sorgu sonuçlarını ve diyagramları gösteren istemcidir. Bağlandıktan sonra `Schemas > lab > Tables` yolunda tabloları, tabloyu açınca `Data` sekmesinde verileri, `lab` schema'sının `ER Diagram` sekmesinde ilişkileri görebilirsin.

## Dosyalar

- `.env`: yerel bağlantı ayarları ve PostgreSQL parolası. Git tarafından yok sayılır.
- `.env.example`: parola içermeyen paylaşılabilir şablon.
- `.local/postgres-runtime/pgsql/bin`: PostgreSQL programları.
- `.local/postgres-data`: asıl veritabanı dosyaları.
- `.local/postgres.log`: sunucu günlüğü.
- `.local/dbeaver-workspace`: bu iş için açılan DBeaver çalışma alanı.

`.local` klasörü public depoya gönderilmez. Git'e kaydedilen SQL dosyaları veritabanını başka bilgisayarda yeniden kurmayı sağlar; çalışan sunucunun fiziksel veri dosyaları paylaşılmaz.

## Sunucuyu başlatma ve durum kontrolü

Proje kökünde PowerShell açıp:

```powershell
.\tools\manage_postgres.ps1 -Action status
.\tools\manage_postgres.ps1 -Action start
```

Normal bir PostgreSQL kurulumu kullanıyorsan bu helper yerine kendi kurulumunun sunucusunu başlat. `.env` içinde o sunucunun portunu (çoğunlukla 5432), kullanıcısını ve parolasını yaz.

`.env` değiştirmek PostgreSQL hesabının parolasını değiştirmez. Başka grup üyeleri bu dosyayı kopyalarken kendi sunucularının parolasını kullanmalıdır.

## Demo ve uygulama kullanıcıları

`APP_USER` tablosundaki Admin / Manager / Technician / Viewer kayıtları örnek uygulama kullanıcılarıdır. Örnek `password_hash` değerleri gerçek parola hash'leri değildir; giriş yapmak için kullanılamaz. Şu an DBeaver bağlantısında kullanılan hesap `postgres` veritabanı hesabıdır.

Resmî dağıtım: https://www.postgresql.org/download/windows/
Resmî DBeaver diyagram açıklaması: https://dbeaver.com/docs/dbeaver/ER-Diagrams/
