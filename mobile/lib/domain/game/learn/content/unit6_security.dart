import '../learn_models.dart';

/// Unit 6 — Penipuan & keamanan.
const LearnUnit unit6 = LearnUnit(
  id: 'u6',
  title: 'Penipuan & Keamanan',
  description:
      'Jaga dompet dari pinjol ilegal, phishing, dan investasi bodong.',
  icon: 'shield',
  lessons: [
    Lesson(
      id: 'u6l1',
      title: 'Awas Pinjol Ilegal',
      description: 'Kenali ciri-ciri pinjaman online ilegal sebelum terjebak.',
      tip:
          'Pinjol ilegal sering minta akses kontak dan galeri, bunga serta dendanya tidak jelas, '
          'dan menagih dengan cara intimidatif. Sebelum pinjam, cek dulu apakah penyelenggaranya '
          'terdaftar dan berizin di OJK.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Mana yang termasuk ciri pinjol ilegal?',
          options: [
            'Terdaftar dan berizin di OJK',
            'Minta akses ke semua kontak dan galeri HP',
            'Biaya dan bunga dijelaskan di awal',
            'Punya layanan pengaduan resmi',
          ],
          correctIndex: 1,
          explanation:
              'Akses kontak dan galeri sering dipakai pinjol ilegal untuk menagih dengan cara mempermalukan.',
        ),
        TrueFalseQuestion(
          prompt:
              'Sebelum meminjam, sebaiknya cek daftar penyelenggara resmi di situs OJK.',
          answer: true,
          explanation:
              'OJK mempublikasikan daftar pinjaman online yang berizin.',
        ),
        FillBlankQuestion(
          prompt:
              'Kalau diteror penagih pinjol ilegal, laporkan ke ___ atau Satgas terkait.',
          options: ['grup arisan', 'OJK', 'tukang parkir'],
          correctIndex: 1,
          explanation:
              'OJK dan satgas pemberantasan aktivitas keuangan ilegal menerima laporan masyarakat.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan: pinjol legal vs ilegal.',
          pairs: [
            MatchPair('Izin usaha', 'Legal: terdaftar di OJK'),
            MatchPair('Akses data HP', 'Ilegal: minta kontak & galeri'),
            MatchPair('Cara menagih', 'Ilegal: ancaman dan sebar data'),
          ],
          explanation:
              'Pinjol legal diawasi OJK; pinjol ilegal sering menyalahgunakan data dan mengintimidasi.',
        ),
        NumericQuestion(
          prompt:
              'Pinjol ilegal memberi pinjaman Rp1.000.000 tapi minta dikembalikan Rp1.600.000 '
              'seminggu kemudian. Berapa rupiah "tambahan" yang harus dibayar?',
          answer: 600000,
          prefix: 'Rp',
          explanation:
              'Rp1.600.000 − Rp1.000.000 = Rp600.000, mahal banget dalam seminggu!',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah aman sebelum pakai pinjaman online.',
          steps: [
            'Pastikan pinjaman benar-benar dibutuhkan',
            'Cek izin penyelenggara di OJK',
            'Baca bunga, biaya, dan denda dengan teliti',
            'Pinjam sesuai kemampuan bayar',
          ],
          explanation:
              'Butuh atau tidak, legal atau tidak, paham biayanya, baru pinjam secukupnya.',
        ),
      ],
    ),
    Lesson(
      id: 'u6l2',
      title: 'Phishing & OTP',
      description: 'Kode OTP itu rahasia, titik.',
      tip:
          'OTP dan PIN jangan pernah dibagikan ke siapa pun, termasuk yang mengaku petugas bank. '
          'Waspada link palsu dan file APK yang dikirim lewat WhatsApp, misalnya berkedok undangan '
          'nikah atau resi kurir. Penipu suka bikin panik biar kamu nggak sempat mikir.',
      questions: [
        TrueFalseQuestion(
          prompt:
              'Petugas bank resmi boleh meminta kode OTP kamu lewat telepon.',
          answer: false,
          explanation:
              'Bank tidak pernah meminta OTP atau PIN. Yang minta pasti patut dicurigai.',
        ),
        MultipleChoiceQuestion(
          prompt:
              'Kamu dapat file "Undangan_Nikah.apk" dari nomor tak dikenal. Sebaiknya…',
          options: [
            'Langsung install biar tahu siapa yang nikah',
            'Teruskan ke grup keluarga',
            'Jangan dibuka, hapus, dan blokir nomornya',
          ],
          correctIndex: 2,
          explanation:
              'File APK bisa berisi aplikasi jahat yang mencuri data dan SMS OTP di HP kamu.',
        ),
        FillBlankQuestion(
          prompt:
              'Penipu sering membuat korban ___ supaya buru-buru menuruti permintaannya.',
          options: ['panik', 'kenyang', 'mengantuk', 'bosan'],
          correctIndex: 0,
          explanation:
              'Ini trik social engineering: bikin panik atau terdesak supaya kamu tidak berpikir jernih.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan modus dengan contohnya.',
          pairs: [
            MatchPair('Phishing', 'Link login palsu mirip situs bank'),
            MatchPair('APK palsu', 'File resi kurir via WhatsApp'),
            MatchPair('Social engineering', 'Mengaku CS bank minta OTP'),
          ],
          explanation: 'Beda modus, tujuannya sama: mencuri data dan uangmu.',
        ),
        OrderStepsQuestion(
          prompt:
              'Terlanjur klik link mencurigakan dan isi data? Urutkan tindakannya.',
          steps: [
            'Segera ganti password dan PIN',
            'Hubungi call center resmi bank',
            'Blokir kartu atau akun jika perlu',
            'Pantau mutasi rekening',
          ],
          explanation:
              'Bergerak cepat: amankan akses, lapor bank, blokir, lalu pantau.',
        ),
        TrueFalseQuestion(
          prompt:
              'Cara aman mengecek info promo bank adalah lewat aplikasi atau situs resminya langsung.',
          answer: true,
          explanation:
              'Jangan percaya link dari pesan acak; buka kanal resmi secara mandiri.',
        ),
      ],
    ),
    Lesson(
      id: 'u6l3',
      title: 'Investasi Bodong',
      description: 'Untung pasti tanpa risiko? Itu red flag!',
      tip:
          'Ingat prinsip 2L: Legal dan Logis. Legal berarti punya izin dari otoritas terkait. '
          'Logis berarti imbal hasilnya masuk akal. Janji untung besar, pasti, dan tanpa risiko, '
          'apalagi harus rekrut anggota baru, adalah tanda bahaya skema Ponzi.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Prinsip "2L" untuk mengecek investasi adalah…',
          options: [
            'Lancar & Lucu',
            'Legal & Logis',
            'Laris & Laku',
            'Lama & Lambat',
          ],
          correctIndex: 1,
          explanation:
              'Cek izinnya (legal) dan kewajaran imbal hasilnya (logis).',
        ),
        TrueFalseQuestion(
          prompt:
              'Investasi yang menjanjikan untung 10% per minggu dan dijamin tanpa risiko itu wajar.',
          answer: false,
          explanation:
              'Semua investasi punya risiko. Untung tinggi yang "pasti" adalah tanda bahaya utama.',
        ),
        FillBlankQuestion(
          prompt:
              'Skema yang membayar anggota lama dengan uang anggota baru disebut skema ___.',
          options: ['Ponzi', 'arisan resmi', 'deposito'],
          correctIndex: 0,
          explanation:
              'Skema Ponzi runtuh begitu anggota baru berhenti masuk, dan banyak yang rugi.',
        ),
        NumericQuestion(
          prompt:
              'Sebuah "investasi" menjanjikan untung 5% per bulan. Kalau dihitung sederhana, '
              'berapa persen untungnya dalam 12 bulan?',
          answer: 60,
          suffix: '%',
          explanation:
              '5% × 12 = 60% per tahun. Janji setinggi itu dan "pasti" patut dicurigai.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan tanda dengan penilaiannya.',
          pairs: [
            MatchPair('Untung pasti tanpa risiko', 'Red flag'),
            MatchPair('Terdaftar di otoritas resmi', 'Tanda baik'),
            MatchPair('Wajib rekrut member baru', 'Tanda skema berantai'),
          ],
          explanation:
              'Cek izin dan waspadai skema member get member dengan janji muluk.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan cara mengecek tawaran investasi.',
          steps: [
            'Tanya produk dan perusahaannya apa',
            'Cek izin di situs otoritas resmi',
            'Nilai apakah imbal hasilnya masuk akal',
            'Baru putuskan, jangan terburu-buru',
          ],
          explanation:
              'Kenali, cek legalitas, uji kelogisan, dan jangan terburu-buru.',
        ),
      ],
    ),
    Lesson(
      id: 'u6l4',
      title: 'Benteng Akun Kamu',
      description: 'Kebiasaan kecil yang bikin akun keuangan aman.',
      tip:
          'Pakai PIN dan password yang unik, aktifkan verifikasi dua langkah (2FA), dan rajin update '
          'aplikasi. Hindari transaksi di Wi-Fi publik, cek mutasi rutin, dan segera lapor serta '
          'blokir kartu kalau hilang atau ada transaksi aneh.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'PIN mana yang paling aman?',
          options: [
            '123456',
            'Tanggal lahir kamu',
            'Kombinasi acak yang tidak mudah ditebak',
          ],
          correctIndex: 2,
          explanation:
              'Hindari angka urut dan tanggal lahir karena mudah ditebak orang.',
        ),
        TrueFalseQuestion(
          prompt:
              'Verifikasi dua langkah (2FA) menambah lapisan keamanan akun.',
          answer: true,
          explanation:
              'Meski password bocor, pelaku masih butuh faktor kedua untuk masuk.',
        ),
        FillBlankQuestion(
          prompt:
              'Sebaiknya hindari transaksi perbankan saat terhubung ke ___ publik.',
          options: ['toilet', 'Wi-Fi', 'taman'],
          correctIndex: 1,
          explanation:
              'Jaringan Wi-Fi publik bisa disadap. Pakai data seluler untuk transaksi.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan kebiasaan dengan manfaatnya.',
          pairs: [
            MatchPair('Update aplikasi', 'Menutup celah keamanan'),
            MatchPair('Cek mutasi rutin', 'Cepat sadar ada transaksi aneh'),
            MatchPair('Password unik', 'Satu bocor, lainnya tetap aman'),
            MatchPair('Aktifkan 2FA', 'Perlu faktor kedua untuk login'),
          ],
          explanation:
              'Kebiasaan kecil ini saling melengkapi jadi benteng berlapis.',
        ),
        OrderStepsQuestion(
          prompt: 'Dompet dan kartu ATM hilang! Urutkan tindakannya.',
          steps: [
            'Hubungi call center resmi bank',
            'Minta blokir kartu',
            'Cek mutasi rekening',
            'Urus kartu pengganti',
          ],
          explanation:
              'Blokir secepatnya supaya kartu tidak disalahgunakan, lalu cek dan urus penggantinya.',
        ),
        NumericQuestion(
          prompt:
              'Kamu punya 4 akun keuangan dan baru 1 yang pakai 2FA. '
              'Berapa akun lagi yang perlu diaktifkan 2FA-nya?',
          answer: 3,
          suffix: 'akun',
          explanation: '4 − 1 = 3 akun. Aktifkan semuanya biar aman!',
        ),
      ],
    ),
  ],
);
