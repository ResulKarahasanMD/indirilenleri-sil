# İndirilenleri Sil

> **English summary.** A macOS app with a Finder toolbar button, a Services entry and a CLI that frees disk space by evicting the local copies of iCloud Drive files that are already uploaded. Nothing is deleted from iCloud: files stay in the cloud and download again when opened. It stands in for `brctl evict`, which no longer exists on current macOS.
> The rest of this README is in Turkish.

iCloud Drive'a yüklenmiş dosyaların yerel kopyalarını diskten kaldıran macOS aracı: Finder araç çubuğu düğmesi, Servisler girdisi ve komut satırı. Dosyalar iCloud'da kalır; açtığında yeniden iner. Güncel macOS'te artık bulunmayan `brctl evict` komutunun yerini tutar.

## Ne yapar, ne yapmaz

- Seçtiğin dosya ve klasörleri tarar, yerel kopyası kaldırılabilecek adayları ve kazanılacak alanı gösterir, onayından sonra kaldırır.
- iCloud'dan hiçbir şey silmez. iCloud dışındaki dosyalara dokunmaz.
- Şunları atlar ve nedenini raporlar: henüz yüklenmemiş ya da yüklenmekte olan dosyalar, yeni değişmiş dosyalar, açık dosyalar, çakışması olanlar, "İndirileni Tut" ile sabitlenmiş öğeler, kendi içeriğini geri indiren uygulamaların kapsayıcıları ve sistemin bırakmayı reddettiği dosyalar.
- Her çalıştırma `~/Library/Logs/IndirilenleriSil/` altına bir kayıt (TSV) yazar. `--verify`, kaldırılanların sonradan geri inip inmediğini denetler.

## Kullanım

- **Finder araç çubuğu:** Finder'da Görüntü → Araç Çubuğunu Özelleştir ile "İndirilenleri Sil" düğmesini ekle. Dosya ya da klasör seçip düğmeye bas.
- **Sağ tık:** menüdeki Servisler altında "İndirilenleri Sil".
- **Komut satırı:**

  ```bash
  APP=~/Applications/IndirilenleriSil.app/Contents/MacOS/IndirilenleriSil
  $APP --dry-run <yol…>            # tara, özet yaz; hiçbir şey kaldırılmaz
  $APP --list <yol…>               # aday ve atlanan yolları da yaz
  $APP --evict <yol…>              # tara ve kaldır, kayıt tut
  $APP --verify <kayıt.tsv|last>   # kaldırılanlar hâlâ bulutta mı
  ```

  Çıkış kodu: 0 istenen her şey yapıldı; 1 bir şey kaldı ya da okunamadı; 2 (`--verify`) kaldırılan öğeler geri inmiş; 64 hatalı kullanım.

## Kurulum

Gerekenler: macOS 27.0.1 ya da üstü, Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) ve bir Developer ID imzalama kimliği.

1. `Config/Shared.xcconfig` içindeki `DEVELOPMENT_TEAM` değerini kendi takım kimliğinle değiştir.
2. `scripts/build-install.sh` betiğini çalıştır. Betik Release derlemesini yapar, `~/Applications/IndirilenleriSil.app` olarak kurar ve Finder uzantısını kaydedip etkinleştirir.
3. Uzantı kapalı kalırsa Sistem Ayarları'ndaki Finder uzantıları listesinden aç ya da şu komutu çalıştır: `pluginkit -e use -i com.rak.indirilenlerisil.FinderExt`
4. İlk çalıştırmada macOS, iCloud Drive, Masaüstü ve Belgeler erişimi için izin ister.

Betik ilk çalıştırmada `Config/Token.xcconfig` dosyasını rastgele bir değerle üretir. Uygulama ile Finder uzantısı bu değeri paylaşır; dosya repoya girmez.

## Test

```bash
xcodegen generate
xcodebuild test -project IndirilenleriSil.xcodeproj -scheme CoreTests \
  -derivedDataPath build/dd -destination 'platform=macOS,arch=arm64'
```

106 Swift Testing testi. Testler geçici bir ev dizininde ve taklit bir iCloud katmanıyla (`Tests/Support/FakeCloud.swift`) çalışır.

## Bilinen sınırlar

- Finder, uzantılara iCloud Drive klasörlerinde sağ tık menüsü vermez; orada araç çubuğu düğmesini ya da Servisler girdisini kullan.
- Kaldırma eşzamansızdır: dosyanın yer tutucuya dönmesi birkaç saniye sürebilir.
- Sistem bazı dosyaları bırakmayı reddeder (`NSFileProviderErrorDomain -2008`); bunlar raporda "bırakılamaz" nedeniyle görünür.

## Lisans

[MIT](LICENSE).
