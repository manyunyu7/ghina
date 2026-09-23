import '../learn_models.dart';

/// Unit 5 — Zakat, sedekah & pajak dasar.
const LearnUnit unit5 = LearnUnit(
  id: 'u5',
  title: 'Zakat, Sedekah & Pajak Dasar',
  description:
      'Berbagi dan taat aturan: kenalan sama zakat, sedekah, NPWP, dan SPT.',
  icon: 'volunteer_activism',
  lessons: [
    Lesson(
      id: 'u5l1',
      title: 'Kenalan sama Zakat',
      description: 'Zakat fitrah vs zakat mal, plus konsep nisab dan haul.',
      tip:
          'Zakat fitrah dibayar menjelang Idulfitri, sedangkan zakat mal dikeluarkan dari harta. '
          'Zakat mal umumnya 2,5% jika harta sudah mencapai nisab (umumnya setara 85 gram emas) '
          'dan dimiliki selama satu tahun (haul). Kalau ragu, tanya ke BAZNAS atau LAZ resmi, ya!',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Zakat yang dibayar menjelang Hari Raya Idulfitri disebut…',
          options: ['Zakat mal', 'Zakat fitrah', 'Zakat profesi', 'Infak'],
          correctIndex: 1,
          explanation:
              'Zakat fitrah wajib ditunaikan di bulan Ramadan sebelum salat Idulfitri.',
        ),
        FillBlankQuestion(
          prompt:
              'Kadar zakat mal yang umum dikenal adalah ___ dari harta yang memenuhi syarat.',
          options: ['10%', '2,5%', '25%', '0,5%'],
          correctIndex: 1,
          explanation:
              'Zakat mal (termasuk zakat penghasilan menurut banyak lembaga) umumnya sebesar 2,5%.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan istilah dengan artinya.',
          pairs: [
            MatchPair('Nisab', 'Batas minimal harta wajib zakat'),
            MatchPair('Haul', 'Harta dimiliki selama satu tahun'),
            MatchPair('Mustahik', 'Penerima zakat'),
            MatchPair('Muzaki', 'Orang yang membayar zakat'),
          ],
          explanation:
              'Nisab dan haul adalah syarat zakat mal; muzaki memberi, mustahik menerima.',
        ),
        NumericQuestion(
          prompt:
              'Harta tabungan Rani Rp100.000.000 sudah mencapai nisab dan haul. '
              'Berapa zakat malnya dengan kadar 2,5%?',
          answer: 2500000,
          prefix: 'Rp',
          explanation: '2,5% × Rp100.000.000 = Rp2.500.000.',
        ),
        TrueFalseQuestion(
          prompt: 'Nisab zakat mal umumnya disetarakan dengan 85 gram emas.',
          answer: true,
          explanation:
              'Banyak lembaga zakat memakai patokan setara 85 gram emas, nilainya ikut harga emas.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Kalau bingung menghitung zakat, sebaiknya…',
          options: [
            'Asal tebak saja',
            'Tanya BAZNAS atau LAZ resmi',
            'Tidak usah bayar',
            'Tunggu 5 tahun lagi',
          ],
          correctIndex: 1,
          explanation:
              'BAZNAS dan Lembaga Amil Zakat resmi punya kalkulator dan layanan konsultasi.',
        ),
      ],
    ),
    Lesson(
      id: 'u5l2',
      title: 'Zakat Penghasilan',
      description: 'Menghitung zakat dari gaji dengan cara sederhana.',
      tip:
          'Banyak lembaga zakat menganjurkan zakat penghasilan 2,5% dari gaji yang sudah mencapai nisab. '
          'Cara hitungnya bisa berbeda antar lembaga, jadi ikuti panduan lembaga resmi yang kamu percaya. '
          'Menyisihkannya di awal bulan bikin lebih ringan!',
      questions: [
        NumericQuestion(
          prompt:
              'Gaji Budi Rp10.000.000 per bulan. Berapa zakat penghasilannya dengan kadar 2,5%?',
          answer: 250000,
          prefix: 'Rp',
          explanation: '2,5% × Rp10.000.000 = Rp250.000.',
        ),
        NumericQuestion(
          prompt:
              'Zakat penghasilan Sari Rp150.000 per bulan. Berapa totalnya dalam setahun?',
          answer: 1800000,
          prefix: 'Rp',
          explanation: 'Rp150.000 × 12 bulan = Rp1.800.000.',
        ),
        TrueFalseQuestion(
          prompt:
              'Semua lembaga zakat pasti memakai cara hitung zakat penghasilan yang persis sama.',
          answer: false,
          explanation:
              'Ada perbedaan pendapat soal detail perhitungan. Ikuti panduan lembaga resmi pilihanmu.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah bayar zakat penghasilan yang rapi.',
          steps: [
            'Cek apakah penghasilan sudah mencapai nisab',
            'Hitung 2,5% dari penghasilan',
            'Sisihkan di awal bulan saat gajian',
            'Salurkan lewat lembaga zakat resmi',
          ],
          explanation:
              'Cek syarat, hitung, sisihkan di awal, lalu salurkan ke lembaga yang amanah.',
        ),
        FillBlankQuestion(
          prompt:
              'Menyisihkan zakat di ___ bulan bikin uangnya nggak keburu terpakai.',
          options: ['akhir', 'awal', 'tengah malam'],
          correctIndex: 1,
          explanation:
              'Sama seperti menabung: bayar yang penting dulu, baru belanja.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Tempat menyalurkan zakat yang disarankan adalah…',
          options: [
            'Akun media sosial yang tidak jelas',
            'Orang yang minta transfer lewat chat acak',
            'BAZNAS atau LAZ resmi',
          ],
          correctIndex: 2,
          explanation:
              'Lembaga resmi lebih terjamin penyalurannya dan biasanya memberi bukti setor zakat.',
        ),
      ],
    ),
    Lesson(
      id: 'u5l3',
      title: 'Sedekah & Infak',
      description: 'Berbagi kapan saja, dan tetap masuk anggaran.',
      tip:
          'Sedekah dan infak sifatnya sukarela, jumlahnya bebas, dan bisa kapan saja. '
          'Supaya rutin dan nggak bikin dompet kaget, buat pos anggaran "memberi" setiap bulan.',
      questions: [
        TrueFalseQuestion(
          prompt: 'Sedekah hanya boleh dilakukan saat bulan Ramadan.',
          answer: false,
          explanation:
              'Sedekah bisa dilakukan kapan saja, tidak terikat waktu tertentu.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Apa beda utama sedekah/infak dengan zakat mal?',
          options: [
            'Sedekah/infak sukarela, zakat mal wajib jika syarat terpenuhi',
            'Sedekah wajib, zakat sukarela',
            'Keduanya sama persis',
          ],
          correctIndex: 0,
          explanation:
              'Zakat mal wajib bila nisab dan haul terpenuhi, sedangkan sedekah dan infak sukarela.',
        ),
        FillBlankQuestion(
          prompt:
              'Biar rutin berbagi, buat pos anggaran ___ di budget bulananmu.',
          options: ['nongkrong', 'memberi', 'gadget', 'diskon'],
          correctIndex: 1,
          explanation:
              'Pos "memberi" membuat sedekah terencana tanpa mengganggu kebutuhan.',
        ),
        NumericQuestion(
          prompt:
              'Dina menyisihkan 2% dari gaji Rp5.000.000 untuk sedekah. Berapa rupiah?',
          answer: 100000,
          prefix: 'Rp',
          explanation: '2% × Rp5.000.000 = Rp100.000.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan contoh dengan jenisnya.',
          pairs: [
            MatchPair('Bayar menjelang Idulfitri', 'Zakat fitrah'),
            MatchPair('2,5% dari tabungan yang capai nisab', 'Zakat mal'),
            MatchPair('Traktir tetangga yang kesusahan', 'Sedekah'),
          ],
          explanation:
              'Zakat punya aturan waktu dan kadar; sedekah bebas bentuk dan waktunya.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan cara membuat kebiasaan berbagi.',
          steps: [
            'Tentukan persentase atau nominal yang nyaman',
            'Masukkan ke anggaran bulanan',
            'Sisihkan saat gajian',
            'Salurkan ke pihak yang tepercaya',
          ],
          explanation:
              'Rencanakan, anggarkan, sisihkan, lalu salurkan dengan bijak.',
        ),
      ],
    ),
    Lesson(
      id: 'u5l4',
      title: 'NPWP & SPT Tahunan',
      description: 'Dasar-dasar pajak pribadi tanpa pusing.',
      tip:
          'NPWP adalah nomor identitas wajib pajak. Untuk orang pribadi, NIK kini juga dapat berfungsi '
          'sebagai NPWP. Setiap tahun wajib pajak melaporkan SPT Tahunan; batas lapor orang pribadi '
          'umumnya akhir Maret. Laporan bisa dilakukan online lewat situs resmi DJP.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'NPWP berfungsi sebagai…',
          options: [
            'Nomor rekening bank',
            'Identitas wajib pajak',
            'Nomor BPJS',
            'Nomor kartu kredit',
          ],
          correctIndex: 1,
          explanation:
              'NPWP adalah Nomor Pokok Wajib Pajak, identitas dalam urusan perpajakan.',
        ),
        TrueFalseQuestion(
          prompt:
              'Untuk orang pribadi, NIK kini juga dapat berfungsi sebagai NPWP.',
          answer: true,
          explanation:
              'Pemerintah mengintegrasikan NIK sebagai NPWP untuk wajib pajak orang pribadi.',
        ),
        FillBlankQuestion(
          prompt:
              'Karyawan biasanya mendapat ___ dari kantor untuk mengisi SPT Tahunan.',
          options: [
            'slip belanja',
            'bukti potong',
            'kartu diskon',
            'struk parkir',
          ],
          correctIndex: 1,
          explanation:
              'Bukti potong berisi penghasilan dan pajak yang sudah dipotong kantor selama setahun.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan istilah pajak dengan artinya.',
          pairs: [
            MatchPair('NPWP', 'Nomor identitas wajib pajak'),
            MatchPair('SPT Tahunan', 'Laporan pajak setiap tahun'),
            MatchPair('DJP', 'Direktorat Jenderal Pajak'),
            MatchPair('Bukti potong', 'Dokumen pajak dari pemberi kerja'),
          ],
          explanation:
              'Kenali istilah dasarnya dulu, urusan pajak jadi jauh lebih santai.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan langkah lapor SPT Tahunan online untuk karyawan.',
          steps: [
            'Minta bukti potong dari kantor',
            'Masuk ke situs resmi DJP',
            'Isi SPT sesuai bukti potong',
            'Kirim dan simpan bukti penerimaan',
          ],
          explanation:
              'Siapkan dokumen, isi di situs resmi, kirim, lalu simpan buktinya.',
        ),
        TrueFalseQuestion(
          prompt:
              'Link lapor pajak dari pesan WhatsApp tak dikenal pasti aman diklik.',
          answer: false,
          explanation:
              'Selalu akses situs resmi DJP secara langsung. Waspada link palsu yang mengatasnamakan pajak.',
        ),
        MultipleChoiceQuestion(
          prompt: 'Batas lapor SPT Tahunan orang pribadi umumnya…',
          options: ['Akhir Januari', 'Akhir Maret', 'Akhir Desember'],
          correctIndex: 1,
          explanation:
              'Umumnya paling lambat akhir Maret. Cek pengumuman resmi DJP setiap tahun ya.',
        ),
      ],
    ),
  ],
);
