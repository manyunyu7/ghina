import '../learn_models.dart';

/// Unit 1 — Dasar Budgeting.
const LearnUnit unit1 = LearnUnit(
  id: 'u1',
  title: 'Dasar Budgeting',
  description: 'Kenali uangmu: mencatat, memilah, dan bikin anggaran pertama.',
  icon: 'account_balance_wallet',
  lessons: [
    Lesson(
      id: 'u1l1',
      title: 'Kenapa Harus Mencatat?',
      description: 'Uang nggak hilang, cuma lupa dicatat.',
      tip:
          'Mencatat pengeluaran bikin kamu tahu ke mana uang pergi. '
          'Banyak orang kaget pas lihat total jajan kecil sebulan. '
          'Nggak perlu sempurna — yang penting rutin tiap hari.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Apa manfaat utama mencatat pengeluaran?',
          options: [
            'Biar kelihatan sibuk',
            'Tahu ke mana uang sebenarnya pergi',
            'Supaya gaji otomatis naik',
            'Biar bisa pamer ke teman',
          ],
          correctIndex: 1,
          explanation:
              'Catatan membantu kamu melihat pola belanja, jadi bisa '
              'memutuskan mana yang perlu dikurangi.',
        ),
        TrueFalseQuestion(
          prompt:
              'Pengeluaran kecil seperti parkir dan jajan nggak perlu dicatat.',
          answer: false,
          explanation:
              'Justru pengeluaran kecil yang sering bocor. Kalau dijumlah '
              'sebulan, totalnya bisa bikin kaget!',
        ),
        FillBlankQuestion(
          prompt: 'Kebiasaan mencatat paling mudah dijaga kalau dilakukan ___.',
          options: ['setahun sekali', 'setiap hari', 'kalau ingat saja'],
          correctIndex: 1,
          explanation:
              'Mencatat tiap hari (atau langsung setelah transaksi) bikin '
              'kamu nggak lupa detailnya.',
        ),
        NumericQuestion(
          prompt:
              'Kamu parkir Rp 5.000 setiap hari kerja. Berapa totalnya '
              'dalam 20 hari kerja?',
          answer: 100000,
          prefix: 'Rp',
          explanation:
              'Rp 5.000 × 20 = Rp 100.000. Kecil-kecil lama-lama jadi bukit!',
        ),
        MultipleChoiceQuestion(
          prompt: 'Kapan waktu terbaik mencatat transaksi?',
          options: [
            'Akhir tahun',
            'Pas dompet sudah kosong',
            'Sesaat setelah transaksi terjadi',
          ],
          correctIndex: 2,
          explanation: 'Langsung dicatat = nggak lupa nominal dan kategorinya.',
        ),
        TrueFalseQuestion(
          prompt:
              'Top up e-wallet sebaiknya dicatat sebagai pindah dana (transfer), '
              'bukan pengeluaran.',
          answer: true,
          explanation:
              'Top up cuma memindahkan uang antar dompet. Pengeluarannya '
              'dicatat saat saldo e-wallet benar-benar dipakai belanja.',
        ),
      ],
    ),
    Lesson(
      id: 'u1l2',
      title: 'Kebutuhan vs Keinginan',
      description: 'Beda "harus" dan "pengen".',
      tip:
          'Kebutuhan adalah hal yang harus dipenuhi untuk hidup dan bekerja, '
          'seperti makan, tempat tinggal, dan transportasi. Keinginan bikin '
          'hidup lebih seru, tapi bisa ditunda. Tanya diri sendiri: "Kalau '
          'nggak beli, apa hidupku terganggu?"',
      questions: [
        MatchPairsQuestion(
          prompt: 'Pasangkan pengeluaran dengan jenisnya.',
          pairs: [
            MatchPair('Bayar kos', 'Kebutuhan'),
            MatchPair('Kopi kekinian tiap hari', 'Keinginan'),
            MatchPair('Sisihkan untuk dana darurat', 'Tabungan'),
          ],
          explanation:
              'Tempat tinggal adalah kebutuhan, kopi kekinian itu keinginan '
              '— boleh, asal terukur. Dana darurat masuk pos tabungan.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Mana yang termasuk KEBUTUHAN?',
          options: [
            'Langganan streaming ketiga',
            'Ongkos transportasi ke kantor',
            'Gadget terbaru padahal yang lama masih bagus',
            'Nonton konser',
          ],
          correctIndex: 1,
          explanation:
              'Ongkos ke kantor dibutuhkan supaya kamu bisa bekerja dan '
              'dapat penghasilan.',
        ),
        TrueFalseQuestion(
          prompt: 'Keinginan itu selalu buruk dan harus dihapus total.',
          answer: false,
          explanation:
              'Keinginan boleh kok! Yang penting dianggarkan dan nggak '
              'mengorbankan kebutuhan atau tabungan.',
        ),
        FillBlankQuestion(
          prompt:
              'Sebelum beli barang keinginan, coba tunggu ___ dulu untuk '
              'meredam belanja impulsif.',
          options: ['5 detik', 'beberapa hari', '10 tahun'],
          correctIndex: 1,
          explanation:
              'Menunda beberapa hari (misalnya aturan 24–72 jam) membantu '
              'kamu tahu apakah benar butuh atau cuma lapar mata.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'HP kamu rusak total dan dipakai untuk kerja ojol. Membeli HP '
              'pengganti yang fungsional termasuk…',
          options: ['Keinginan', 'Kebutuhan', 'Investasi saham'],
          correctIndex: 1,
          explanation:
              'Kalau HP alat kerja, penggantinya adalah kebutuhan. Tapi '
              'model termahal belum tentu — pilih yang sesuai fungsi.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan cara bijak memutuskan pembelian.',
          steps: [
            'Tanya: ini kebutuhan atau keinginan?',
            'Cek apakah ada anggarannya bulan ini',
            'Bandingkan harga dan alternatif',
            'Baru putuskan beli atau tunda',
          ],
          explanation:
              'Mulai dari alasan, cek anggaran, bandingkan, baru ambil '
              'keputusan. Dompet aman, hati tenang.',
        ),
      ],
    ),
    Lesson(
      id: 'u1l3',
      title: 'Aturan 50/30/20',
      description: 'Resep simpel bagi-bagi gaji.',
      tip:
          'Aturan 50/30/20 membagi penghasilan: 50% untuk kebutuhan, 30% '
          'untuk keinginan, dan 20% untuk tabungan atau bayar utang. Ini '
          'panduan umum, bukan hukum — silakan sesuaikan dengan kondisimu.',
      questions: [
        MatchPairsQuestion(
          prompt: 'Pasangkan porsi dengan pos-nya di aturan 50/30/20.',
          pairs: [
            MatchPair('50%', 'Kebutuhan'),
            MatchPair('30%', 'Keinginan'),
            MatchPair('20%', 'Tabungan & bayar utang'),
          ],
          explanation:
              'Setengah untuk kebutuhan, 30% untuk gaya hidup, dan 20% '
              'untuk masa depanmu.',
        ),
        NumericQuestion(
          prompt:
              'Gaji kamu Rp 5.000.000. Menurut aturan 50/30/20, berapa '
              'porsi untuk tabungan?',
          answer: 1000000,
          prefix: 'Rp',
          explanation: '20% × Rp 5.000.000 = Rp 1.000.000.',
        ),
        NumericQuestion(
          prompt:
              'Dengan gaji Rp 4.000.000, berapa porsi KEBUTUHAN menurut '
              'aturan 50/30/20?',
          answer: 2000000,
          prefix: 'Rp',
          explanation: '50% × Rp 4.000.000 = Rp 2.000.000.',
        ),
        TrueFalseQuestion(
          prompt:
              'Kalau biaya hidup di kotamu tinggi, porsi 50/30/20 boleh '
              'disesuaikan, misalnya 60/20/20.',
          answer: true,
          explanation:
              'Aturan ini panduan awal. Yang penting tetap ada porsi untuk '
              'menabung.',
        ),
        FillBlankQuestion(
          prompt: 'Cicilan utang dalam aturan 50/30/20 masuk ke porsi ___.',
          options: ['30% keinginan', '20% tabungan & utang', 'nggak dihitung'],
          correctIndex: 1,
          explanation:
              'Porsi 20% dipakai untuk memperbaiki kondisi keuangan: '
              'menabung dan melunasi utang. (Cicilan wajib minimum sering '
              'juga dimasukkan ke kebutuhan — yang penting konsisten.)',
        ),
        MultipleChoiceQuestion(
          prompt: 'Nonton bioskop dan jajan boba masuk porsi berapa?',
          options: ['50%', '20%', '30%'],
          correctIndex: 2,
          explanation: 'Hiburan dan jajan = keinginan, porsi 30%.',
        ),
      ],
    ),
    Lesson(
      id: 'u1l4',
      title: 'Bikin Anggaran Bulanan',
      description: 'Kasih setiap rupiah tugasnya.',
      tip:
          'Anggaran = rencana sebelum uang dipakai. Mulai dari penghasilan, '
          'catat pengeluaran wajib, sisihkan tabungan, lalu bagi sisanya ke '
          'kategori. Di akhir bulan, bandingkan rencana dengan kenyataan.',
      questions: [
        OrderStepsQuestion(
          prompt: 'Urutkan langkah bikin anggaran bulanan.',
          steps: [
            'Hitung total penghasilan bulan ini',
            'Catat pengeluaran wajib (kos, listrik, cicilan)',
            'Sisihkan tabungan di awal',
            'Bagi sisanya ke kategori lain',
            'Pantau dan evaluasi di akhir bulan',
          ],
          explanation:
              'Dari penghasilan ke pengeluaran wajib, tabungan, sisanya, '
              'lalu evaluasi. Siklus ini diulang tiap bulan.',
        ),
        NumericQuestion(
          prompt:
              'Penghasilan Rp 4.500.000. Kos Rp 1.200.000, makan '
              'Rp 1.500.000, transport Rp 500.000, tabungan Rp 700.000. '
              'Berapa sisa untuk kategori lain?',
          answer: 600000,
          prefix: 'Rp',
          explanation:
              '1.200.000 + 1.500.000 + 500.000 + 700.000 = 3.900.000. '
              '4.500.000 − 3.900.000 = Rp 600.000.',
        ),
        TrueFalseQuestion(
          prompt: 'Anggaran sekali dibuat tidak boleh diubah sama sekali.',
          answer: false,
          explanation:
              'Anggaran itu hidup. Kalau ada perubahan penghasilan atau '
              'kebutuhan, sesuaikan saja.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Kamu dapat THR atau bonus. Langkah paling bijak menurut '
              'prinsip anggaran adalah…',
          options: [
            'Langsung habiskan, kan rezeki',
            'Rencanakan: sebagian tabung/lunasi utang, sebagian untuk senang-senang',
            'Diamkan di dompet tanpa rencana',
          ],
          correctIndex: 1,
          explanation:
              'Uang tambahan juga perlu tugas. Bagi dengan rencana supaya '
              'nggak habis tanpa jejak.',
        ),
        FillBlankQuestion(
          prompt:
              'Pengeluaran yang jumlahnya sama tiap bulan, seperti kos, '
              'disebut pengeluaran ___.',
          options: ['tetap', 'impulsif', 'darurat', 'musiman'],
          correctIndex: 0,
          explanation:
              'Pengeluaran tetap mudah diprediksi, jadi masukkan duluan ke '
              'anggaran.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan contoh dengan jenis pengeluarannya.',
          pairs: [
            MatchPair('Sewa kos', 'Tetap'),
            MatchPair('Belanja dapur', 'Variabel'),
            MatchPair('Kado nikahan teman', 'Tak rutin'),
          ],
          explanation:
              'Kos tetap tiap bulan, belanja dapur naik-turun, dan kado '
              'datangnya sesekali — tetap perlu disiapkan!',
        ),
      ],
    ),
    Lesson(
      id: 'u1l5',
      title: 'Godaan Belanja',
      description: 'Diskon, FOMO, dan kebocoran halus.',
      tip:
          'Diskon bikin kita merasa hemat padahal tetap keluar uang. FOMO '
          '(takut ketinggalan) bikin ikut-ikutan belanja. Dan "latte factor" '
          'adalah pengeluaran kecil rutin yang diam-diam menggerus tabungan.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Flash sale 70%! Tapi barangnya nggak kamu butuhkan. Itu…',
          options: [
            'Hemat 70%',
            'Tetap pengeluaran 30% yang nggak perlu',
            'Investasi jangka panjang',
          ],
          correctIndex: 1,
          explanation:
              'Kalau nggak butuh, uang yang keluar tetap "hilang". Hemat '
              'terbaik adalah nggak beli.',
        ),
        NumericQuestion(
          prompt:
              'Kamu beli kopi kekinian Rp 25.000 sebanyak 20 kali sebulan. '
              'Berapa totalnya sebulan?',
          answer: 500000,
          prefix: 'Rp',
          explanation:
              'Rp 25.000 × 20 = Rp 500.000. Ini contoh "latte factor"!',
        ),
        NumericQuestion(
          prompt:
              'Kalau kebiasaan Rp 500.000 per bulan itu dipotong setengah, '
              'berapa yang bisa ditabung dalam 12 bulan?',
          answer: 3000000,
          prefix: 'Rp',
          explanation:
              'Rp 250.000 × 12 = Rp 3.000.000 setahun. Lumayan banget!',
        ),
        TrueFalseQuestion(
          prompt:
              'FOMO adalah rasa takut ketinggalan tren yang bisa memicu belanja impulsif.',
          answer: true,
          explanation:
              'FOMO = fear of missing out. Sadari perasaannya, lalu kembali '
              'ke anggaran.',
        ),
        FillBlankQuestion(
          prompt:
              'Salah satu cara mengurangi belanja impulsif online adalah '
              'menghapus kartu yang ___ di aplikasi belanja.',
          options: ['tersimpan', 'kedaluwarsa', 'berwarna emas'],
          correctIndex: 0,
          explanation:
              'Kalau harus input ulang pembayaran, ada jeda untuk berpikir '
              'lagi sebelum checkout.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah evaluasi anggaran di akhir bulan.',
          steps: [
            'Kumpulkan catatan transaksi sebulan',
            'Bandingkan realisasi dengan anggaran',
            'Temukan kategori yang jebol',
            'Tentukan perbaikan untuk bulan depan',
          ],
          explanation:
              'Evaluasi rutin bikin anggaran bulan depan lebih realistis.',
        ),
      ],
    ),
  ],
);
