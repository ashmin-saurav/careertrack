import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  // --- STATE ---
  final String _selectedExam = "NTPC";

  // ==================================================
  // 1. MASTER LISTS (REUSABLE DATA)
  // ==================================================

  // COMMON MATHS
  final List<String> _commonMaths = [
    "Number System", "BODMAS & Simplification", "Decimals & Fractions", "LCM & HCF",
    "Average", "Ratio & Proportions", "Partnership", "Mixture & Alligation",
    "Percentage", "Profit & Loss", "Simple & Compound Interest",
    "Time & Work", "Pipes & Cisterns",
    "Time, Speed & Distance", "Problems on Trains", "Boats & Streams",
    "Mensuration (2D & 3D)", "Elementary Algebra", "Geometry",
    "Trigonometry", "Heights & Distances",
    "Statistics", "Data Interpretation (DI)",
    "Square Root", "Age Calculations", "Calendar & Clock"
  ];

  // COMMON REASONING
  final List<String> _commonReasoning = [
    "Analogies", "Classification (Odd One Out)", "Missing Numbers",
    "Series Completion", "Coding-Decoding", "Mathematical Operations",
    "Jumbling",
    "Directions & Distances", "Blood Relations",
    "Sitting Arrangement", "Puzzles (Floor/Box/Day)",
    "Clock & Calendar", "Order & Ranking", "Syllogism", "Venn Diagrams",
    "Counting Figures", "Mirror & Water Images",
    "Statement-Conclusion", "Statement-Arguments", "Statement-Course of Action",
    "Data Sufficiency", "Miscellaneous"
  ];

  // GK & CURRENT AFFAIRS
  final List<String> _bossGK = [
    "HEADER:CURRENT AFFAIRS",
    "National & International", "Govt Schemes", "Appointments",
    "Summits & Conferences", "Sports Tournaments", "Awards & Honours",
    "HEADER:RAILWAYS GK",
    "Railway Zones & HQs", "Railway Budget History", "Trains of India",
    "Railway Boards & Facts", "Recent Railway Developments",
    "HEADER:HISTORY",
    "Indus Valley", "Vedic Age", "Buddhism & Jainism", "Maurya & Gupta",
    "Delhi Sultanate", "Mughal Empire", "Marathas", "Revolt of 1857",
    "Indian National Congress", "Gandhian Era", "Governor Generals",
    "HEADER:POLITY",
    "Constitution Making", "Fundamental Rights & Duties", "President & VP",
    "Parliament", "Judiciary (SC/HC)", "Amendments", "Panchayati Raj",
    "HEADER:GEOGRAPHY",
    "Solar System", "Atmosphere", "Rivers of India", "National Parks",
    "Soils & Agriculture", "Transport System", "Census 2011",
    "HEADER:ECONOMY",
    "National Income", "Inflation", "RBI & Banking", "Budget & Taxes",
    "HEADER:STATIC GK",
    "Dances & Festivals", "Books & Authors", "Important Days", "International Orgs"
  ];

  // SCIENCE
  final List<String> _bossScience = [
    "HEADER:PHYSICS",
    "Units & Measurements", "Motion & Force", "Friction",
    "Gravitation", "Work, Power & Energy", "Heat & Thermodynamics",
    "Sound", "Light (Optics)", "Electricity", "Magnetism", "Sources of Energy",
    "HEADER:CHEMISTRY",
    "Matter & Atoms", "Periodic Table", "Chemical Bonding", "Reactions",
    "Acids, Bases & Salts", "Metals & Non-Metals", "Carbon Compounds",
    "HEADER:BIOLOGY",
    "The Cell", "Tissues", "Human Systems (Digestive/Resp/Circulatory)",
    "Control & Coordination", "Reproduction", "Heredity", "Diseases",
    "Environment & Ecosystem"
  ];

  // COMPUTERS
  final List<String> _commonComputers = [
    "Computer Architecture", "Input/Output Devices", "Storage", "Networking",
    "OS", "MS Office", "Internet & Email", "Data Representation",
    "Computer Viruses", "Web Browsers", "Shortcuts & Abbreviations"
  ];

  // ==================================================
  // 2. DATA MAPPING
  // ==================================================
  late final Map<String, List<Map<String, dynamic>>> _syllabusData;

  @override
  void initState() {
    super.initState();
    _syllabusData = {
      "NTPC": [
        {"subject": "Mathematics", "color": const Color(0xFF2962FF), "gradient": [Color(0xFF448AFF), Color(0xFF2979FF)], "icon": Icons.functions_rounded, "topics": _commonMaths},
        {"subject": "Reasoning", "color": const Color(0xFFD500F9), "gradient": [Color(0xFFE040FB), Color(0xFFD500F9)], "icon": Icons.psychology_rounded, "topics": _commonReasoning},
        {"subject": "General Science", "color": const Color(0xFF00C853), "gradient": [Color(0xFF69F0AE), Color(0xFF00E676)], "icon": Icons.science_rounded, "topics": _bossScience},
        {"subject": "General Awareness", "color": const Color(0xFFFF6D00), "gradient": [Color(0xFFFF9E80), Color(0xFFFF6E40)], "icon": Icons.public_rounded, "topics": _bossGK},
        {"subject": "Comp. Applications", "color": Colors.indigo, "gradient": [Color(0xFF5C6BC0), Color(0xFF3949AB)], "icon": Icons.computer, "topics": _commonComputers},
      ],
    };
  }

  // Only NTPC Tab
  final List<String> _examTabs = ["NTPC"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      // --- COMPACT APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Syllabus & Topics",
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: Column(
        children: [
          // --- 1. COMPACT RIBBON (NTPC Only) ---
          Container(
            height: 50,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200))
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _examTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final exam = _examTabs[index];
                const isSelected = true; // Always true for single item

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected ? null : Border.all(color: Colors.grey.shade300),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    exam,
                    style: GoogleFonts.poppins(
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
          ),

          // --- 2. MAIN CONTENT ---
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // Section Title
                  Row(
                    children: [
                      Container(width: 3, height: 16, color: const Color(0xFF1E293B)),
                      const SizedBox(width: 8),
                      Text("MODULES", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey[600], letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Syllabus Cards
                  if (_syllabusData.containsKey(_selectedExam))
                    ..._syllabusData[_selectedExam]!.map((subject) {
                      return _buildCompactSubjectCard(
                        subject['subject'],
                        subject['color'],
                        subject['gradient'],
                        subject['icon'],
                        subject['topics'],
                      );
                    })
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: CircularProgressIndicator(color: Colors.blue[800], strokeWidth: 3),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET 2: Compact Subject Card (Static) ---
  Widget _buildCompactSubjectCard(String title, Color color, List<Color> gradient, IconData icon, List<String> items) {
    int topicCount = items.where((i) => !i.startsWith("HEADER:")).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B)),
          ),
          // 🟢 REMOVED 0% Progress
          subtitle: Text(
            "$topicCount Topics",
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[500]),
          ),
          children: [
            Container(height: 1, color: Colors.grey[100]),
            const SizedBox(height: 10),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                if (item.startsWith("HEADER:")) {
                  return _buildSectionHeader(item.replaceAll("HEADER:", ""), color);
                }
                return _buildTopicTile(item, color);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET 3: Small Section Header ---
  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: color.withOpacity(0.1))),
        ],
      ),
    );
  }

  // --- WIDGET 4: Compact Topic Tile (Static - No InkWell) ---
  Widget _buildTopicTile(String title, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Static Dot Icon
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }
}