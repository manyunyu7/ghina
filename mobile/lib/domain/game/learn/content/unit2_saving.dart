import '../learn_models.dart';

/// Unit 2 — Dana Darurat & Menabung.
const LearnUnit unit2 = LearnUnit(
  id: 'u2',
  title: 'Dana Darurat & Menabung',
  description: 'Bangun bantalan aman dan wujudkan tujuanmu.',
  icon: 'savings',
  lessons: [
    Lesson(
      id: 'u2l1',
      title: 'Apa Itu Dana Darurat?',
      description: 'Payung sebelum hujan.',
      tip:
          'Dana darurat adalah uang yang disiapkan khusus untuk kejadian '
          'tak terduga: kena PHK, sakit, atau motor rusak. Tujuannya supaya '
          'kamu nggak perlu berutang saat musibah datang.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Mana yang paling tepat dibayar pakai dana darurat?',
          options: [
            'Liburan dadakan ke Bali',
            'Diskon gadget akhir tahun',
            'Biaya servis motor yang rusak mendadak untuk kerja',
            'Tiket konser idola',
          ],
          correctIndex: 2,
          explanation:
              'Dana darurat untuk kejadian mendadak yang penting, bukan '
              'untuk keinginan.',
        ),
        TrueFalseQuestion(
          prompt:
              'Dana darurat membantu kita nggak perlu pinjam uang saat musibah.',
          answer: true,
          explanation:
              'Dengan dana darurat, kamu terhindar dari utang berbunga '
              'tinggi seperti pinjol saat kepepet.',
        ),
        FillBlankQuestion(
          prompt:
              'Dana darurat sebaiknya disimpan ___ dari uang belanja harian.',
          options: ['dicampur', 'terpisah', 'di dompet'],
          correctIndex: 1,
          explanation:
              'Kalau dicampur, dana darurat gampang terpakai tanpa sadar. '
              'Pisahkan rekeningnya!',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan kejadian dengan kategorinya.',
          pairs: [
            MatchPair('Kena PHK', 'Darurat penghasilan'),
            MatchPair('Promo tanggal kembar', 'Bukan darurat'),
            MatchPair('Biaya berobat mendadak', 'Darurat kesehatan'),
          ],
          explanation:
              'PHK dan sakit mendadak adalah darurat. Promo itu godaan, '
              'bukan darurat.',
        ),
        TrueFalseQuestion(
          prompt: 'Setelah dana darurat terpakai, sebaiknya diisi ulang lagi.',
          answer: true,
          explanation:
              'Dana darurat itu seperti ban serep: setelah dipakai, '
              'siapkan lagi untuk kejadian berikutnya.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Kapan sebaiknya mulai mengumpulkan dana darurat?',
          options: [
            'Nanti kalau sudah kaya',
            'Sedini mungkin, walau mulai dari nominal kecil',
            'Setelah semua keinginan terpenuhi',
          ],
          correctIndex: 1,
          explanation:
              'Mulai kecil tapi konsisten jauh lebih baik daripada menunggu '
              'momen sempurna.',
        ),
      ],
    ),
    Lesson(
      id: 'u2l2',
      title: 'Berapa Besarnya?',
      description: 'Hitung target dana daruratmu.',
      tip:
          'Panduan umum: lajang sekitar 3–6 kali pengeluaran bulanan, sudah '
          'menikah atau punya tanggungan sekitar 6–12 kali. Yang dihitung '
          'adalah PENGELUARAN, bukan gaji. Makin banyak tanggungan atau makin '
          'tidak tetap penghasilan, makin besar targetnya.',
      questions: [
        NumericQuestion(
          prompt:
              'Pengeluaran bulananmu Rp 3.000.000. Kalau targetnya 6 kali '
              'pengeluaran, berapa dana darurat yang perlu dikumpulkan?',
          answer: 18000000,
          prefix: 'Rp',
          explanation: 'Rp 3.000.000 × 6 = Rp 18.000.000.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Dasar perhitungan dana darurat adalah…',
          options: [
            'Pengeluaran bulanan',
            'Gaji tahunan',
            'Saldo e-wallet',
            'Harga HP terbaru',
          ],
          correctIndex: 0,
          explanation:
              'Dana darurat harus menutup biaya hidup saat penghasilan '
              'berhenti, jadi hitung dari pengeluaran.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan kondisi dengan panduan umum target dana darurat.',
          pairs: [
            MatchPair('Lajang', '3–6× pengeluaran'),
            MatchPair('Menikah, punya anak', '6–12× pengeluaran'),
            MatchPair('Freelancer, penghasilan tak tetap', 'Lebih besar lagi'),
          ],
          explanation:
              'Makin banyak tanggungan dan makin tidak pasti penghasilan, '
              'makin besar bantalan yang dibutuhkan.',
        ),
        NumericQuestion(
          prompt:
              'Target dana darurat Rp 12.000.000. Kamu menabung Rp 500.000 '
              'per bulan. Berapa bulan sampai tercapai?',
          answer: 24,
          suffix: 'bulan',
          explanation:
              'Rp 12.000.000 ÷ Rp 500.000 = 24 bulan. Pelan tapi pasti!',
        ),
        TrueFalseQuestion(
          prompt:
              'Driver ojol dengan penghasilan harian naik-turun sebaiknya punya dana darurat lebih besar.',
          answer: true,
          explanation:
              'Penghasilan tidak tetap berarti risiko bulan sepi lebih '
              'besar, jadi bantalannya perlu lebih tebal.',
        ),
        FillBlankQuestion(
          prompt:
              'Kalau target terasa berat, mulai dulu dengan target kecil, '
              'misalnya ___ bulan pengeluaran.',
          options: ['1', '100', '0'],
          correctIndex: 0,
          explanation:
              'Target 1 bulan dulu bikin semangat. Setelah tercapai, '
              'naikkan bertahap.',
        ),
      ],
    ),
    Lesson(
      id: 'u2l3',
      title: 'Simpan di Mana?',
      description: 'Aman, likuid, dan nggak gampang tergoda.',
      tip:
          'Dana darurat harus likuid (mudah dicairkan) dan nilainya stabil. '
          'Pilihan umum: rekening tabungan terpisah, deposito jangka pendek, '
          'atau reksa dana pasar uang. Hindari aset yang harganya naik-turun '
          'tajam seperti saham atau kripto.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Sifat utama tempat menyimpan dana darurat adalah…',
          options: [
            'Untungnya paling tinggi',
            'Sulit dicairkan biar nggak tergoda',
            'Mudah dicairkan dan nilainya stabil',
          ],
          correctIndex: 2,
          explanation:
              'Saat darurat, kamu butuh uangnya cepat dan utuh, bukan '
              'sedang turun nilainya.',
        ),
        TrueFalseQuestion(
          prompt:
              'Saham cocok jadi tempat utama dana darurat karena potensi untungnya besar.',
          answer: false,
          explanation:
              'Harga saham bisa turun tepat saat kamu butuh uang. Saham '
              'lebih cocok untuk tujuan jangka panjang.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan instrumen dengan kecocokannya untuk dana darurat.',
          pairs: [
            MatchPair('Tabungan terpisah', 'Cocok, bisa diambil kapan saja'),
            MatchPair('Reksa dana pasar uang', 'Cocok, risiko relatif rendah'),
            MatchPair('Kripto', 'Kurang cocok, harga fluktuatif'),
          ],
          explanation:
              'Pilih yang likuid dan stabil. Aset fluktuatif sebaiknya '
              'untuk uang yang nggak dibutuhkan dalam waktu dekat.',
        ),
        FillBlankQuestion(
          prompt:
              'Istilah untuk aset yang mudah dan cepat dicairkan adalah ___.',
          options: ['volatil', 'likuid', 'inflasi', 'agunan'],
          correctIndex: 1,
          explanation:
              'Likuid = gampang diubah jadi uang tunai tanpa rugi besar.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Kenapa sebaiknya dana darurat tidak ditaruh di e-wallet yang '
              'dipakai jajan sehari-hari?',
          options: [
            'Karena e-wallet ilegal',
            'Karena terlalu gampang terpakai untuk belanja',
            'Karena e-wallet tidak bisa diisi',
          ],
          correctIndex: 1,
          explanation:
              'Bukan soal ilegal — tapi godaan checkout itu nyata. Pisahkan '
              'supaya dana darurat tetap utuh.',
        ),
        TrueFalseQuestion(
          prompt:
              'Deposito biasanya bisa dicairkan sebelum jatuh tempo, tapi '
              'kadang dengan penalti.',
          answer: true,
          explanation:
              'Makanya kalau pakai deposito, pilih tenor pendek atau '
              'simpan sebagian dana di tabungan biasa.',
        ),
      ],
    ),
    Lesson(
      id: 'u2l4',
      title: 'Tujuan Keuangan SMART',
      description: 'Dari "pengen nabung" jadi rencana nyata.',
      tip:
          'Tujuan SMART: Specific (jelas), Measurable (terukur), Achievable '
          '(realistis), Relevant (penting buatmu), dan Time-bound (ada '
          'tenggat). Contoh: "Nabung Rp 6 juta untuk DP motor dalam 12 bulan."',
      questions: [
        MatchPairsQuestion(
          prompt: 'Pasangkan huruf SMART dengan artinya.',
          pairs: [
            MatchPair('S', 'Spesifik / jelas'),
            MatchPair('M', 'Terukur'),
            MatchPair('A', 'Realistis dicapai'),
            MatchPair('T', 'Ada batas waktu'),
          ],
          explanation:
              'Plus R = Relevant: tujuannya penting buat hidupmu, bukan '
              'sekadar ikut-ikutan.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Mana tujuan yang paling SMART?',
          options: [
            'Pengen kaya',
            'Nabung yang banyak tahun ini',
            'Nabung Rp 6.000.000 untuk DP motor dalam 12 bulan',
          ],
          correctIndex: 2,
          explanation:
              'Jelas tujuannya, jelas angkanya, jelas waktunya. SMART!',
        ),
        NumericQuestion(
          prompt:
              'Target Rp 6.000.000 dalam 12 bulan. Berapa yang perlu '
              'ditabung per bulan?',
          answer: 500000,
          prefix: 'Rp',
          explanation: 'Rp 6.000.000 ÷ 12 = Rp 500.000 per bulan.',
        ),
        NumericQuestion(
          prompt:
              'Kamu mau liburan dengan biaya Rp 3.600.000 dalam 6 bulan. '
              'Berapa tabungan per bulan?',
          answer: 600000,
          prefix: 'Rp',
          explanation: 'Rp 3.600.000 ÷ 6 = Rp 600.000 per bulan.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah merencanakan tujuan keuangan.',
          steps: [
            'Tentukan tujuan dan alasannya',
            'Hitung biaya yang dibutuhkan',
            'Tentukan tenggat waktu',
            'Hitung tabungan per bulan',
            'Mulai menabung dan pantau progres',
          ],
          explanation:
              'Tujuan → biaya → waktu → cicilan tabungan → eksekusi. '
              'Tinggal konsisten!',
        ),
        FillBlankQuestion(
          prompt:
              'Tujuan yang nggak punya tenggat waktu gampang ___ terus-menerus.',
          options: ['tercapai', 'ditunda', 'berbunga'],
          correctIndex: 1,
          explanation: 'Tenggat bikin kita punya alasan untuk mulai sekarang.',
        ),
      ],
    ),
    Lesson(
      id: 'u2l5',
      title: 'Trik Menabung',
      description: 'Bayar dirimu sendiri dulu!',
      tip:
          '"Bayar diri sendiri dulu" artinya menyisihkan tabungan tepat '
          'setelah gajian, bukan menabung sisa. Autodebet ke rekening '
          'terpisah bikin prosesnya otomatis. Metode amplop/pos membagi uang '
          'ke wadah per kebutuhan.',
      questions: [
        OrderStepsQuestion(
          prompt: 'Urutkan alur "bayar diri sendiri dulu" saat gajian.',
          steps: [
            'Gaji masuk ke rekening',
            'Langsung pindahkan porsi tabungan',
            'Bayar pengeluaran wajib',
            'Sisanya untuk kebutuhan harian dan jajan',
          ],
          explanation:
              'Tabungan diambil di awal, jadi nggak tergantung ada sisa atau '
              'nggak di akhir bulan.',
        ),
        TrueFalseQuestion(
          prompt:
              'Menabung dari sisa uang di akhir bulan adalah cara paling efektif.',
          answer: false,
          explanation:
              'Sisa di akhir bulan sering nol. Tabung di awal biar pasti!',
        ),
        MultipleChoiceQuestion(
          prompt: 'Apa keuntungan fitur autodebet ke rekening tabungan?',
          options: [
            'Bunga otomatis jadi dobel',
            'Menabung jadi otomatis tanpa perlu ingat',
            'Rekening nggak bisa kena biaya admin',
          ],
          correctIndex: 1,
          explanation:
              'Otomatis = nggak bergantung pada niat dan ingatan. Konsisten '
              'tanpa drama.',
        ),
        FillBlankQuestion(
          prompt:
              'Metode ___ membagi uang ke beberapa pos, misalnya makan, '
              'transport, dan hiburan.',
          options: ['arisan', 'amplop', 'gesek tunai', 'cicilan'],
          correctIndex: 1,
          explanation:
              'Metode amplop bisa pakai amplop fisik atau "kantong" digital '
              'di rekening/e-wallet.',
        ),
        NumericQuestion(
          prompt:
              'Gaji Rp 4.000.000 dan kamu "bayar diri sendiri dulu" 15%. '
              'Berapa yang langsung ditabung?',
          answer: 600000,
          prefix: 'Rp',
          explanation: '15% × Rp 4.000.000 = Rp 600.000.',
        ),
        NumericQuestion(
          prompt:
              'Kamu menyisihkan Rp 20.000 setiap hari selama 30 hari. '
              'Berapa terkumpul?',
          answer: 600000,
          prefix: 'Rp',
          explanation:
              'Rp 20.000 × 30 = Rp 600.000. Receh yang rajin jadi jutaan!',
        ),
        TrueFalseQuestion(
          prompt:
              'Arisan bisa membantu disiplin menyisihkan uang, tapi bukan '
              'tempat menabung yang menambah nilai uang.',
          answer: true,
          explanation:
              'Arisan melatih rutin menyetor, tapi uang yang kamu terima '
              'sama dengan total setoranmu — tanpa bunga atau imbal hasil.',
        ),
      ],
    ),
  ],
);
