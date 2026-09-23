import '../learn_models.dart';

/// Unit 4 — Investasi Dasar.
const LearnUnit unit4 = LearnUnit(
  id: 'u4',
  title: 'Investasi Dasar',
  description:
      'Bikin uangmu ikut kerja: inflasi, bunga majemuk, reksa dana, saham, emas, dan cara mengelola risiko.',
  icon: 'trending_up',
  lessons: [
    Lesson(
      id: 'u4l1',
      title: 'Inflasi: Si Pencuri Diam-Diam',
      description: 'Kenapa uang Rp100 ribu tahun depan nggak sesakti hari ini?',
      tip:
          'Inflasi adalah kenaikan harga barang dan jasa secara umum dari waktu ke waktu. '
          'Artinya, dengan jumlah uang yang sama, barang yang bisa kamu beli makin sedikit. '
          'Uang yang cuma didiamkan akan pelan-pelan kehilangan daya belinya.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Inflasi artinya...',
          options: [
            'Harga barang dan jasa secara umum naik',
            'Gaji otomatis naik tiap bulan',
            'Harga barang turun terus',
            'Uang di tabungan bertambah sendiri',
          ],
          correctIndex: 0,
          explanation:
              'Inflasi adalah kenaikan harga secara umum, sehingga daya beli uang menurun.',
        ),
        NumericQuestion(
          prompt:
              'Nasi goreng langganan harganya Rp20.000. Kalau inflasi misalnya 5% setahun, kira-kira berapa harganya tahun depan?',
          answer: 21000,
          prefix: 'Rp',
          explanation:
              '5% × Rp20.000 = Rp1.000. Jadi harganya kira-kira Rp21.000.',
        ),
        TrueFalseQuestion(
          prompt:
              'Menyimpan uang tunai di bawah kasur selama 10 tahun membuat daya belinya tetap sama.',
          answer: false,
          explanation:
              'Jumlah uangnya tetap, tapi karena inflasi, barang yang bisa dibeli makin sedikit.',
        ),
        FillBlankQuestion(
          prompt:
              'Supaya daya beli terjaga, imbal hasil investasi idealnya ___ dari inflasi.',
          options: ['lebih rendah', 'sama persis', 'lebih tinggi'],
          correctIndex: 2,
          explanation:
              'Kalau imbal hasil di atas inflasi, nilai uangmu benar-benar bertumbuh.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Tabunganmu dapat bunga misalnya 2% setahun, sementara inflasi misalnya 4%. Yang terjadi pada daya belimu?',
          options: [
            'Naik 2%',
            'Turun kira-kira 2%',
            'Naik 6%',
            'Tidak berubah',
          ],
          correctIndex: 1,
          explanation:
              'Imbal hasil riil kira-kira 2% − 4% = −2%. Uangnya bertambah, tapi daya belinya menyusut.',
        ),
      ],
    ),
    Lesson(
      id: 'u4l2',
      title: 'Keajaiban Bunga Majemuk',
      description:
          'Bunga yang berbunga. Waktu adalah sahabat terbaik investor.',
      tip:
          'Bunga majemuk artinya imbal hasil ikut diinvestasikan lagi, sehingga tahun berikutnya kamu dapat imbal hasil dari pokok plus hasil sebelumnya. '
          'Makin lama waktunya, makin terasa efeknya. Itulah kenapa mulai lebih awal, walau kecil, sangat berarti.',
      questions: [
        NumericQuestion(
          prompt:
              'Rp1.000.000 diinvestasikan dengan imbal hasil misalnya 10% per tahun, dimajemukkan. Berapa nilainya setelah 2 tahun?',
          answer: 1210000,
          prefix: 'Rp',
          explanation:
              'Tahun 1: Rp1.100.000. Tahun 2: Rp1.100.000 × 1,1 = Rp1.210.000.',
        ),
        TrueFalseQuestion(
          prompt:
              'Pada bunga majemuk, bunga tahun kedua dihitung dari pokok ditambah bunga tahun pertama.',
          answer: true,
          explanation:
              'Itulah bedanya dengan bunga sederhana: hasilnya ikut berbunga.',
        ),
        NumericQuestion(
          prompt:
              'Rp2.000.000 dengan imbal hasil misalnya 5% per tahun, dimajemukkan selama 2 tahun. Berapa hasil akhirnya?',
          answer: 2205000,
          prefix: 'Rp',
          explanation:
              'Tahun 1: Rp2.100.000. Tahun 2: Rp2.100.000 × 1,05 = Rp2.205.000.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Siapa yang kemungkinan punya hasil lebih besar di usia 50, dengan setoran dan imbal hasil yang sama per tahun?',
          options: [
            'Ayu, mulai investasi umur 35',
            'Budi, mulai investasi umur 25',
            'Sama saja, umur nggak berpengaruh',
          ],
          correctIndex: 1,
          explanation:
              'Budi punya waktu 10 tahun lebih lama untuk membiarkan bunga majemuk bekerja.',
        ),
        FillBlankQuestion(
          prompt:
              'Aturan 72: bagi 72 dengan persen imbal hasil per tahun untuk memperkirakan berapa tahun uang jadi ___.',
          options: ['setengah', 'dua kali lipat', 'nol', 'tiga kali lipat'],
          correctIndex: 1,
          explanation:
              'Aturan 72 adalah jalan pintas kasar untuk menebak waktu uang berlipat dua.',
        ),
        NumericQuestion(
          prompt:
              'Pakai aturan 72: dengan imbal hasil misalnya 8% per tahun, kira-kira berapa tahun uangmu jadi dua kali lipat?',
          answer: 9,
          suffix: 'tahun',
          explanation: '72 ÷ 8 = 9 tahun. Ingat, ini perkiraan kasar ya.',
        ),
      ],
    ),
    Lesson(
      id: 'u4l3',
      title: 'Deposito & Reksa Dana',
      description: 'Pintu masuk investasi yang ramah pemula.',
      tip:
          'Deposito adalah simpanan berjangka di bank dengan bunga yang sudah disepakati; mencairkannya sebelum jatuh tempo bisa kena penalti. '
          'Reksa dana adalah wadah yang mengumpulkan dana banyak investor lalu dikelola oleh manajer investasi, dan diawasi OJK. '
          'Jenisnya antara lain reksa dana pasar uang, pendapatan tetap, campuran, dan saham, dengan tingkat risiko yang berbeda.',
      questions: [
        MatchPairsQuestion(
          prompt: 'Cocokkan jenis reksa dana dengan isi utamanya!',
          pairs: [
            MatchPair('Pasar uang', 'Deposito & surat utang jangka pendek'),
            MatchPair('Pendapatan tetap', 'Mayoritas obligasi'),
            MatchPair('Campuran', 'Kombinasi saham & obligasi'),
            MatchPair('Saham', 'Mayoritas saham'),
          ],
          explanation:
              'Makin banyak porsi saham, biasanya potensi imbal hasil dan risikonya makin tinggi.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Siapa yang mengelola dana di reksa dana?',
          options: [
            'Nasabah sendiri',
            'Manajer investasi',
            'Teller bank',
            'Influencer saham',
          ],
          correctIndex: 1,
          explanation:
              'Manajer investasi yang profesional dan berizin mengelola dana reksa dana.',
        ),
        TrueFalseQuestion(
          prompt:
              'Reksa dana pasar uang umumnya punya risiko lebih rendah dibanding reksa dana saham.',
          answer: true,
          explanation:
              'Isinya instrumen jangka pendek yang cenderung stabil, jadi fluktuasinya lebih kecil.',
        ),
        NumericQuestion(
          prompt:
              'Deposito Rp10.000.000 dengan bunga misalnya 4% per tahun. Berapa bunganya setelah 1 tahun (sebelum pajak)?',
          answer: 400000,
          prefix: 'Rp',
          explanation:
              '4% × Rp10.000.000 = Rp400.000. Bunga deposito biasanya masih dipotong pajak.',
        ),
        FillBlankQuestion(
          prompt: 'Mencairkan deposito sebelum jatuh tempo bisa dikenakan ___.',
          options: ['bonus', 'penalti', 'cashback'],
          correctIndex: 1,
          explanation:
              'Deposito punya jangka waktu. Cair lebih awal biasanya kena penalti, jadi pakai dana yang memang nggak segera dibutuhkan.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Lembaga yang mengawasi industri reksa dana di Indonesia adalah...',
          options: ['BPS', 'Kemendikbud', 'OJK', 'Pertamina'],
          correctIndex: 2,
          explanation:
              'OJK (Otoritas Jasa Keuangan) mengawasi manajer investasi dan produk reksa dana.',
        ),
      ],
    ),
    Lesson(
      id: 'u4l4',
      title: 'Saham & Emas',
      description: 'Jadi pemilik perusahaan, atau simpan kilau emas?',
      tip:
          'Membeli saham berarti ikut memiliki sebagian kecil perusahaan. Keuntungan bisa datang dari kenaikan harga dan dividen, tapi harganya bisa naik-turun tajam. '
          'Di Bursa Efek Indonesia, saham diperdagangkan per lot, dan 1 lot = 100 lembar. '
          'Emas sering dipakai sebagai lindung nilai jangka panjang, tapi ada selisih harga beli dan jual, jadi kurang cocok untuk jangka pendek.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Membeli saham sebuah perusahaan artinya kamu...',
          options: [
            'Meminjamkan uang ke perusahaan',
            'Ikut memiliki sebagian perusahaan',
            'Jadi karyawan perusahaan',
            'Dapat bunga tetap tiap bulan',
          ],
          correctIndex: 1,
          explanation:
              'Pemegang saham adalah pemilik sebagian perusahaan, sesuai porsi sahamnya.',
        ),
        NumericQuestion(
          prompt:
              'Harga sebuah saham misalnya Rp1.000 per lembar. Berapa uang yang dibutuhkan untuk membeli 1 lot (belum termasuk biaya transaksi)?',
          answer: 100000,
          prefix: 'Rp',
          explanation: '1 lot = 100 lembar. 100 × Rp1.000 = Rp100.000.',
        ),
        FillBlankQuestion(
          prompt:
              'Bagian laba perusahaan yang dibagikan ke pemegang saham disebut ___.',
          options: ['dividen', 'denda', 'cicilan', 'premi'],
          correctIndex: 0,
          explanation:
              'Dividen adalah pembagian laba ke pemegang saham. Nggak semua perusahaan membagikannya setiap tahun.',
        ),
        TrueFalseQuestion(
          prompt: 'Harga saham dijamin selalu naik dalam jangka pendek.',
          answer: false,
          explanation:
              'Harga saham bisa naik atau turun, kadang tajam. Nggak ada jaminan keuntungan.',
        ),
        NumericQuestion(
          prompt:
              'Kamu beli emas 1 gram seharga misalnya Rp1.000.000, dan harga jual kembalinya hari itu Rp900.000. Kalau langsung dijual, berapa ruginya?',
          answer: 100000,
          prefix: 'Rp',
          explanation:
              'Rp1.000.000 − Rp900.000 = Rp100.000. Selisih harga beli-jual ini bikin emas lebih cocok untuk jangka panjang.',
        ),
        MatchPairsQuestion(
          prompt: 'Cocokkan instrumen dengan cirinya!',
          pairs: [
            MatchPair('Saham', 'Kepemilikan perusahaan, harga fluktuatif'),
            MatchPair('Emas', 'Lindung nilai jangka panjang'),
            MatchPair('Deposito', 'Bunga sesuai kesepakatan di bank'),
          ],
          explanation:
              'Tiap instrumen punya karakter sendiri. Pilih sesuai tujuan dan jangka waktumu.',
        ),
      ],
    ),
    Lesson(
      id: 'u4l5',
      title: 'Profil Risiko & Diversifikasi',
      description: 'Jangan taruh semua telur di satu keranjang.',
      tip:
          'Umumnya, makin tinggi potensi imbal hasil, makin tinggi juga risikonya. Kenali profil risikomu: konservatif, moderat, atau agresif. '
          'Sebar investasimu ke beberapa instrumen (diversifikasi) supaya satu kerugian nggak menghancurkan semuanya. '
          'Siapkan dana darurat dulu, dan selalu cek legalitas produk di OJK.',
      questions: [
        OrderStepsQuestion(
          prompt: 'Urutkan langkah sebelum mulai investasi!',
          steps: [
            'Siapkan dana darurat',
            'Tentukan tujuan dan jangka waktu',
            'Kenali profil risikomu',
            'Cek legalitas produk dan pengelolanya di OJK',
            'Mulai investasi dengan diversifikasi',
          ],
          explanation:
              'Fondasi dulu, baru investasi. Dana darurat mencegahmu terpaksa menjual investasi saat butuh uang mendadak.',
        ),
        TrueFalseQuestion(
          prompt:
              'Produk yang menjanjikan untung tinggi tanpa risiko sama sekali patut dicurigai.',
          answer: true,
          explanation:
              'High return selalu datang bersama high risk. Janji untung besar dan pasti adalah ciri khas investasi bodong.',
        ),
        FillBlankQuestion(
          prompt:
              'Menyebar uang ke beberapa jenis investasi supaya risiko nggak menumpuk di satu tempat disebut ___.',
          options: ['spekulasi', 'likuidasi', 'diversifikasi', 'inflasi'],
          correctIndex: 2,
          explanation:
              'Diversifikasi = jangan taruh semua telur di satu keranjang.',
        ),
        MatchPairsQuestion(
          prompt: 'Cocokkan profil risiko dengan contoh sikapnya!',
          pairs: [
            MatchPair(
              'Konservatif',
              'Utamakan uang aman, hasil kecil nggak apa-apa',
            ),
            MatchPair(
              'Moderat',
              'Mau sedikit naik-turun demi hasil lebih baik',
            ),
            MatchPair(
              'Agresif',
              'Siap naik-turun tajam demi potensi hasil tinggi',
            ),
          ],
          explanation:
              'Nggak ada profil yang paling benar. Yang penting cocok dengan tujuan dan ketenangan hatimu.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Uang untuk bayar kuliah 6 bulan lagi sebaiknya ditaruh di instrumen yang...',
          options: [
            'Paling berisiko supaya cepat berlipat',
            'Rendah risiko dan mudah dicairkan',
            'Dikunci 10 tahun',
          ],
          correctIndex: 1,
          explanation:
              'Untuk kebutuhan jangka pendek, keamanan dan kemudahan cair lebih penting daripada potensi hasil tinggi.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Temanmu mengajak ikut investasi "pasti untung 10% per bulan". Langkah pertama yang tepat?',
          options: [
            'Transfer dulu sebelum kuotanya habis',
            'Ajak keluarga ikut biar untung bareng',
            'Cek legalitasnya di OJK dan waspadai janji untung pasti',
            'Percaya karena temanmu sudah dapat untung',
          ],
          correctIndex: 2,
          explanation:
              'Imbal hasil pasti setinggi itu nggak wajar. Cek izinnya di OJK dan jangan tergiur testimoni.',
        ),
      ],
    ),
  ],
);
