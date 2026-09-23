import '../learn_models.dart';

/// Unit 3 — Utang, Kartu Kredit & Paylater.
const LearnUnit unit3 = LearnUnit(
  id: 'u3',
  title: 'Utang, Kartu Kredit & Paylater',
  description:
      'Kenali utang sebelum utang yang mengenalimu. Bunga, kartu kredit, paylater, sampai cara melunasinya.',
  icon: 'credit_card',
  lessons: [
    Lesson(
      id: 'u3l1',
      title: 'Utang Produktif vs Konsumtif',
      description:
          'Nggak semua utang itu jahat, tapi semua utang harus dibayar.',
      tip:
          'Utang produktif dipakai untuk sesuatu yang bisa menambah penghasilan atau nilai, misalnya modal usaha. '
          'Utang konsumtif dipakai untuk barang yang nilainya cepat turun atau habis dipakai, seperti gadget terbaru atau liburan. '
          'Sebagai panduan umum, total cicilan sebaiknya nggak lebih dari sekitar 30% penghasilan bulanan.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Mana contoh utang produktif?',
          options: [
            'Cicilan HP baru biar nggak ketinggalan tren',
            'Pinjaman modal untuk beli gerobak usaha jualan',
            'Utang buat staycation akhir pekan',
            'Paylater untuk beli sepatu diskon',
          ],
          correctIndex: 1,
          explanation:
              'Gerobak usaha bisa menghasilkan pemasukan, jadi utangnya bersifat produktif.',
        ),
        TrueFalseQuestion(
          prompt:
              'Utang konsumtif selalu dilarang dan nggak boleh diambil sama sekali.',
          answer: false,
          explanation:
              'Nggak selalu dilarang, tapi harus sangat hati-hati dan sesuai kemampuan bayar karena nggak menambah penghasilan.',
        ),
        NumericQuestion(
          prompt:
              'Gaji Dimas Rp8.000.000 per bulan. Kalau pakai panduan cicilan maksimal 30%, berapa batas total cicilannya per bulan?',
          answer: 2400000,
          prefix: 'Rp',
          explanation:
              '30% × Rp8.000.000 = Rp2.400.000. Di atas itu, keuangan mulai sesak napas.',
        ),
        FillBlankQuestion(
          prompt:
              'Sebelum berutang, tanya dulu: apakah aku ___ membayar cicilannya tiap bulan?',
          options: ['pasti ingin', 'sanggup', 'terpaksa'],
          correctIndex: 1,
          explanation:
              'Kemampuan bayar adalah kunci. Keinginan saja nggak cukup untuk melunasi cicilan.',
        ),
        MatchPairsQuestion(
          prompt: 'Cocokkan jenis utangnya!',
          pairs: [
            MatchPair('Modal usaha katering', 'Produktif'),
            MatchPair('Cicilan konsol game', 'Konsumtif'),
            MatchPair('Kursus skill yang menaikkan gaji', 'Investasi diri'),
          ],
          explanation:
              'Utang yang menambah penghasilan atau kemampuanmu cenderung lebih sehat daripada utang untuk gaya hidup.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Rina sudah punya cicilan 35% dari gajinya. Tawaran kredit motor baru datang. Sebaiknya?',
          options: [
            'Ambil aja, mumpung ada promo DP ringan',
            'Tunda dulu dan kurangi cicilan yang ada',
            'Ambil, nanti bayarnya pakai pinjaman lain',
          ],
          correctIndex: 1,
          explanation:
              'Cicilannya sudah melewati panduan 30%. Menambah utang baru bikin risiko gagal bayar makin tinggi.',
        ),
      ],
    ),
    Lesson(
      id: 'u3l2',
      title: 'Cara Kerja Bunga',
      description: 'Bunga itu "harga sewa" uang. Yuk pahami biar nggak kaget.',
      tip:
          'Saat berutang, kamu bayar pokok plus bunga. Bunga flat dihitung dari pokok awal sepanjang masa pinjaman, '
          'sedangkan bunga efektif dihitung dari sisa pokok yang makin lama makin kecil. '
          'Angka bunga flat sering terlihat kecil, jadi selalu hitung total yang harus dibayar.',
      questions: [
        FillBlankQuestion(
          prompt:
              'Bunga ___ dihitung dari pokok awal, walaupun utangmu sudah dicicil.',
          options: ['efektif', 'flat', 'majemuk', 'nol'],
          correctIndex: 1,
          explanation:
              'Bunga flat selalu dihitung dari pokok awal, jadi besarnya bunga tiap bulan sama.',
        ),
        NumericQuestion(
          prompt:
              'Pinjam Rp12.000.000 dengan bunga flat misalnya 10% per tahun, dicicil 12 bulan. Berapa cicilan per bulan?',
          answer: 1100000,
          prefix: 'Rp',
          explanation:
              'Bunga setahun = 10% × Rp12.000.000 = Rp1.200.000. Total Rp13.200.000 ÷ 12 = Rp1.100.000.',
        ),
        TrueFalseQuestion(
          prompt:
              'Pada bunga efektif, porsi bunga di cicilan makin kecil seiring sisa utang berkurang.',
          answer: true,
          explanation:
              'Karena bunga efektif dihitung dari sisa pokok, bunganya ikut turun saat pokok berkurang.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Yang paling penting dibandingkan saat memilih pinjaman adalah...',
          options: [
            'Warna brosurnya',
            'Cicilan per bulan saja',
            'Total biaya: pokok, bunga, dan biaya lainnya',
            'Seberapa cepat cair',
          ],
          correctIndex: 2,
          explanation:
              'Cicilan kecil bisa menipu kalau tenornya panjang. Bandingkan total yang harus dibayar, termasuk biaya admin dan denda.',
        ),
        MatchPairsQuestion(
          prompt: 'Cocokkan istilahnya!',
          pairs: [
            MatchPair('Pokok', 'Jumlah uang yang dipinjam'),
            MatchPair('Tenor', 'Lama waktu pinjaman'),
            MatchPair('Bunga', 'Biaya atas uang yang dipinjam'),
            MatchPair('Denda', 'Biaya karena telat bayar'),
          ],
          explanation:
              'Kenali istilah ini biar kamu bisa baca perjanjian pinjaman dengan percaya diri.',
        ),
        TrueFalseQuestion(
          prompt:
              'Tenor lebih panjang selalu berarti total bunga yang dibayar lebih kecil.',
          answer: false,
          explanation:
              'Tenor panjang bikin cicilan per bulan lebih ringan, tapi total bunganya biasanya malah lebih besar.',
        ),
      ],
    ),
    Lesson(
      id: 'u3l3',
      title: 'Kartu Kredit Tanpa Drama',
      description:
          'Kartu kredit bisa jadi teman atau musuh. Tergantung cara bayarnya.',
      tip:
          'Kartu kredit itu meminjam uang bank untuk dibayar nanti. Kalau tagihan dibayar penuh sebelum jatuh tempo, biasanya nggak kena bunga. '
          'Kalau cuma bayar minimum, sisa tagihan kena bunga dan bisa menumpuk cepat. Telat bayar? Siap-siap kena denda.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Cara paling sehat membayar tagihan kartu kredit adalah...',
          options: [
            'Bayar minimum tiap bulan',
            'Bayar penuh sebelum jatuh tempo',
            'Bayar kalau ingat aja',
            'Bayar pakai kartu kredit lain',
          ],
          correctIndex: 1,
          explanation:
              'Bayar penuh sebelum jatuh tempo menghindarkanmu dari bunga dan denda.',
        ),
        NumericQuestion(
          prompt:
              'Tagihan kartu kreditmu Rp2.000.000. Kalau minimum pembayarannya misalnya 10%, berapa minimal yang harus dibayar?',
          answer: 200000,
          prefix: 'Rp',
          explanation:
              '10% × Rp2.000.000 = Rp200.000. Tapi ingat, sisa Rp1.800.000 akan kena bunga!',
        ),
        TrueFalseQuestion(
          prompt:
              'Kalau selalu bayar minimum, utang kartu kredit bisa butuh waktu sangat lama untuk lunas.',
          answer: true,
          explanation:
              'Sebagian besar pembayaran minimum habis untuk bunga, jadi pokoknya turun pelan sekali.',
        ),
        FillBlankQuestion(
          prompt: 'Limit kartu kredit itu batas ___, bukan tambahan gaji.',
          options: ['pinjaman', 'tabungan', 'bonus'],
          correctIndex: 0,
          explanation:
              'Limit adalah uang bank yang harus kamu kembalikan. Belanjalah sesuai kemampuan bayar, bukan sesuai limit.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan kebiasaan sehat memakai kartu kredit!',
          steps: [
            'Belanja hanya yang sudah dianggarkan',
            'Catat setiap transaksi kartu kredit',
            'Cek lembar tagihan saat terbit',
            'Bayar penuh sebelum jatuh tempo',
          ],
          explanation:
              'Anggarkan, catat, cek tagihan, lalu lunasi. Kartu kredit aman kalau dipakai dengan disiplin.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Tarik tunai pakai kartu kredit umumnya...',
          options: [
            'Gratis dan tanpa bunga',
            'Lebih murah dari transfer biasa',
            'Kena biaya dan bunga yang langsung berjalan',
          ],
          correctIndex: 2,
          explanation:
              'Tarik tunai kartu kredit biasanya kena biaya tambahan dan bunga sejak hari penarikan. Hindari kecuali darurat banget.',
        ),
      ],
    ),
    Lesson(
      id: 'u3l4',
      title: 'Paylater: Enak Sekarang, Bayar Nanti',
      description: 'Klik "bayar nanti" itu gampang. Bayarnya yang nggak.',
      tip:
          'Paylater adalah utang, sama seperti kartu kredit atau pinjaman. Riwayat pembayarannya bisa tercatat di SLIK OJK, '
          'yang dilihat bank saat kamu mengajukan KPR atau kredit lain. Telat bayar paylater bisa bikin pengajuan kredit di masa depan ditolak.',
      questions: [
        TrueFalseQuestion(
          prompt: 'Paylater bukan utang, cuma metode pembayaran biasa.',
          answer: false,
          explanation:
              'Paylater adalah utang: kamu memakai uang pihak lain dan wajib mengembalikannya, sering kali plus biaya.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Riwayat pembayaran kredit, termasuk paylater dari lembaga resmi, bisa tercatat di...',
          options: [
            'Kartu Keluarga',
            'SLIK OJK',
            'KTP elektronik',
            'Buku tabungan',
          ],
          correctIndex: 1,
          explanation:
              'SLIK OJK mencatat riwayat kredit. Catatan telat bayar bisa mempersulit pengajuan kredit nanti.',
        ),
        NumericQuestion(
          prompt:
              'Kamu belanja Rp1.200.000 pakai paylater, dicicil 3 bulan dengan biaya misalnya 2,5% per bulan dari harga belanja. Berapa total biayanya?',
          answer: 90000,
          prefix: 'Rp',
          explanation:
              '2,5% × Rp1.200.000 = Rp30.000 per bulan. Selama 3 bulan jadi Rp90.000 ekstra.',
        ),
        FillBlankQuestion(
          prompt:
              'Paylater bikin belanja terasa ringan, jadi gampang memicu belanja ___.',
          options: ['terencana', 'impulsif', 'hemat', 'bulanan'],
          correctIndex: 1,
          explanation:
              'Karena nggak terasa keluar uang saat itu, paylater gampang bikin kita belanja tanpa pikir panjang.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Ada diskon 50% tapi kamu nggak punya dananya, cuma ada limit paylater. Langkah bijak?',
          options: [
            'Checkout sekarang, diskon nggak datang dua kali',
            'Pakai paylater lalu pikirkan nanti',
            'Tunda 24 jam dan cek apakah barang ini memang butuh dan ada di anggaran',
          ],
          correctIndex: 2,
          explanation:
              'Aturan tunggu 24 jam membantu memisahkan kebutuhan dari godaan diskon.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah sebelum menekan tombol paylater!',
          steps: [
            'Tanya: ini kebutuhan atau keinginan?',
            'Cek apakah ada di anggaran bulan ini',
            'Hitung total biaya dan cicilannya',
            'Pastikan cicilan muat di penghasilan bulanan',
          ],
          explanation:
              'Mulai dari kebutuhan, lalu anggaran, biaya, dan kemampuan bayar. Kalau ada yang gagal, jangan checkout.',
        ),
      ],
    ),
    Lesson(
      id: 'u3l5',
      title: 'Strategi Lunas Utang',
      description:
          'Snowball atau avalanche? Pilih strategimu dan mulai bebas utang.',
      tip:
          'Metode snowball: lunasi utang dengan saldo terkecil dulu supaya cepat merasa menang. '
          'Metode avalanche: lunasi utang dengan bunga tertinggi dulu supaya total bunga paling hemat. '
          'Di kedua metode, utang lain tetap dibayar minimum. Yang penting: jangan gali lubang tutup lubang!',
      questions: [
        MatchPairsQuestion(
          prompt: 'Cocokkan metodenya!',
          pairs: [
            MatchPair('Snowball', 'Saldo terkecil dulu'),
            MatchPair('Avalanche', 'Bunga tertinggi dulu'),
            MatchPair(
              'Gali lubang tutup lubang',
              'Utang baru untuk bayar utang lama',
            ),
          ],
          explanation:
              'Snowball menang di motivasi, avalanche menang di hemat bunga. Gali lubang tutup lubang? Hindari!',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Kamu punya utang A (bunga 2%/bulan) dan B (bunga 4%/bulan). Dengan metode avalanche, lunasi dulu...',
          options: [
            'Utang A',
            'Utang B',
            'Dua-duanya bareng dengan porsi sama',
          ],
          correctIndex: 1,
          explanation: 'Avalanche fokus ke bunga tertinggi, jadi utang B dulu.',
        ),
        TrueFalseQuestion(
          prompt:
              'Mengambil pinjaman baru untuk menutup cicilan lama adalah strategi pelunasan yang sehat.',
          answer: false,
          explanation:
              'Itu gali lubang tutup lubang. Utangnya cuma pindah tempat, sering malah bertambah bunga dan biaya.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah memulai rencana bebas utang!',
          steps: [
            'Daftar semua utang beserta saldo dan bunganya',
            'Pilih metode snowball atau avalanche',
            'Bayar minimum semua utang lainnya',
            'Arahkan uang ekstra ke utang prioritas',
          ],
          explanation:
              'Mulai dengan data lengkap, pilih strategi, jaga semua cicilan tetap lancar, lalu gempur satu per satu.',
        ),
        NumericQuestion(
          prompt:
              'Sisa utangmu Rp3.000.000. Kalau kamu bisa bayar Rp500.000 per bulan (anggap tanpa bunga), berapa bulan sampai lunas?',
          answer: 6,
          suffix: 'bulan',
          explanation:
              'Rp3.000.000 ÷ Rp500.000 = 6 bulan. Tambah sedikit bayarnya, makin cepat lunasnya!',
        ),
        FillBlankQuestion(
          prompt:
              'Metode ___ cocok buat kamu yang butuh semangat dari kemenangan kecil yang cepat.',
          options: ['avalanche', 'minimum payment', 'snowball'],
          correctIndex: 2,
          explanation:
              'Snowball melunasi saldo terkecil dulu, jadi kamu cepat merasakan satu utang benar-benar lunas.',
        ),
      ],
    ),
  ],
);
