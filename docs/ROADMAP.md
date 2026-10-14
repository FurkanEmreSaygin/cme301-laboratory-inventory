# Yapılanlar ve sonraki işler

Durum: 14 Ekim 2026.

## Tamamlandı

- [x] Proje formu ve ayrıntılı proje planı incelendi.
- [x] 12 çekirdek + 4 isteğe bağlı tabloya dayanan veri modeli hazırlandı.
- [x] PK, FK, UNIQUE, CHECK, indeks ve view tanımları oluşturuldu.
- [x] FEFO çıkış, giriş, transfer ve fire prosedürleri hazırlandı.
- [x] Denetim kayıtları ve uyarı taraması eklendi.
- [x] Mevcut stok / hareket geçmişi karşılaştırma view'ı eklendi.
- [x] Sentetik örnek veride eksik açılış hareketi tamamlandı.
- [x] Hata kodunu da doğrulayan testler düzenlendi: 70 PASS / 0 FAIL.
- [x] Eşzamanlı iki stok çıkışı ve aynı lota iki giriş doğrulandı.
- [x] Miktarları farklı birimler arasında toplamayan rapor sorgusu düzeltildi.
- [x] Tam şema (16 tablo / 25 ilişki) ve stok modeli için DBeaver ERD kaynakları oluşturuldu.
- [x] Sadeleştirilmiş stok modeli PNG / SVG görselleri hazırlandı.
- [x] SQL teslim paketi, bağlantı rehberi ve Git yapılandırması hazırlandı.

## Öncelikli sonraki adımlar

- [ ] DBeaver JDBC sürücüsü ve kullanıcı girişini tamamlamak.
- [ ] `.erd` dosyalarının DBeaver içindeki görsel açılışını doğrulamak.
- [ ] Tam şema ve stok modeli PNG'lerini DBeaver'dan dışa aktarmak.
- [ ] Sunum görselinde isteğe bağlılığı uçtaki daireyle, PK'ya katılımı çizgi tipiyle ayırmak.
- [ ] Sunum çıktısında kullanıcı ilişkilerini de görünür tutmak.
- [ ] ISA / alt tür eşlemesini küçük bir EER görseliyle açıklamak.
- [ ] FEFO örneğini sunumda 5 + 3 = 8 birimlik demo ile göstermek.

## Uygulama ve rapor aşaması

- [ ] Normalizasyon adımlarını fonksiyonel bağımlılıklarla gerekçelendirmek.
- [ ] SQL sorgularını ilişkisel cebir ifadeleriyle birlikte rapora koymak.
- [ ] 10.000+ stok hareketi içeren sentetik performans veri setini üretmek.
- [ ] İndeks öncesi / sonrası EXPLAIN ANALYZE, boyut ve süre ölçümleri yapmak.
- [ ] Günlük `CALL lab.sp_refresh_alerts();` zamanlayıcısını kurmak.
- [ ] GUI'de gerçek parola hash'i, parametrik sorgular ve oturum doğrulamasını uygulamak.
- [ ] Depolama sıcaklığı uyumluluğu ve sipariş durum geçişlerini tamamlamak.
- [ ] Sipariş, cihaz ve bakım modüllerinin uygulama kapsamını ekipçe kesinleştirmek.
- [ ] Yedekleme / geri yükleme örneği ve demo videosu hazırlamak.

## Açık tasarım kararları

- SKT bütün lotlarda zorunlu kalacak mı, SKT'siz sarf malzemeleri desteklenecek mi?
- Uygulama tek güvenilir backend hesabıyla mı, ayrı PostgreSQL login'leriyle mi bağlanacak?
- Günlük uyarı taraması hangi zamanlayıcıyla çalışacak?
- Hangi isteğe bağlı modüller Phase 2 teslimine yetiştirilecek?
