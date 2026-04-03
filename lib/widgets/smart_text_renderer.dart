import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

class SmartTextRenderer extends StatelessWidget {
  final String text;
  final Color textColor;
  final double devicePixelRatio;
  final bool selectable;

  const SmartTextRenderer({
    super.key,
    required this.text,
    required this.textColor,
    required this.devicePixelRatio,
    this.selectable = true,
  });

  String _cleanText(String input) {
    // 1. Handle literal newlines coming from API
    String processed = input.replaceAll(r'\n', '\n');
    // 2. Fix MathJax style fractions
    processed = processed.replaceAll(r'\dfrac', r'\frac');
    return processed;
  }

  @override
  Widget build(BuildContext context) {
    final String cleanData = _cleanText(text);

    // 🟢 1. FONT: NotoSansDevanagari for clear Hindi & English mix
    final safeFont = GoogleFonts.notoSansDevanagari(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: textColor,
      height: 1.6,
    );

    // 🟢 2. SMART DETECTION LOGIC
    // We ONLY switch to the heavy Markdown engine for Tables, Images, or Code Blocks.
    // We intentionally DO NOT switch for Lists (* item) or Bold (**text**)
    // to protect Reasoning symbols (e.g., "A * B") from turning into italics.
    final bool hasComplexMarkdown =
        cleanData.contains('![') ||      // Images
            cleanData.contains('|') ||       // Tables
            cleanData.contains('```');       // Code blocks
    // Removed: cleanData.startsWith('* ') to prevent single star issues

    Widget content;
    if (!hasComplexMarkdown) {
      // Use our Custom Manual Renderer (Safe for Reasoning Topics)
      content = _ManualRichTextRenderer(
        text: cleanData,
        style: safeFont,
        selectable: selectable,
      );
    } else {
      // Use Native Markdown for complex Tables/Images
      content = _NativeMarkdown(
        data: cleanData,
        textColor: textColor,
        devicePixelRatio: devicePixelRatio,
        baseStyle: safeFont,
        selectable: selectable,
      );
    }

    if (!selectable) {
      // Allows clicks to pass through (e.g., for Quiz Options)
      return IgnorePointer(child: content);
    }
    return content;
  }
}

// ---------------------------------------------------------------------
// MANUAL RENDERER (Safe for "Reasoning * Symbols" & Fixes "**")
// ---------------------------------------------------------------------
class _ManualRichTextRenderer extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool selectable;

  const _ManualRichTextRenderer({
    required this.text,
    required this.style,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double maxWidth = (constraints.maxWidth > 0 && constraints.maxWidth.isFinite)
          ? constraints.maxWidth
          : 300.0;

      List<InlineSpan> spans = [];

      // 1. Split by Block Math $$...$$
      final blockParts = text.split(RegExp(r'\$\$'));

      for (int i = 0; i < blockParts.length; i++) {
        if (i % 2 != 0) {
          // --- BLOCK MATH ---
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  blockParts[i],
                  mathStyle: MathStyle.display,
                  textStyle: style.copyWith(fontSize: 18),
                  onErrorFallback: (_) => Text("\$\$${blockParts[i]}\$\$",
                      style: style.copyWith(color: Colors.red)),
                ),
              ),
            ),
          ));
          if (i < blockParts.length - 1) spans.add(const TextSpan(text: "\n"));
        } else {
          // --- TEXT + INLINE MATH ---
          if (blockParts[i].isNotEmpty) {
            spans.addAll(_parseInlineMath(blockParts[i], maxWidth));
          }
        }
      }

      if (selectable) {
        return SelectableText.rich(
          TextSpan(children: spans),
          style: style,
          textAlign: TextAlign.left,
        );
      } else {
        return RichText(
          text: TextSpan(children: spans, style: style),
          textAlign: TextAlign.left,
        );
      }
    });
  }

  List<InlineSpan> _parseInlineMath(String input, double maxWidth) {
    List<InlineSpan> spans = [];
    final parts = input.split(RegExp(r'(?<!\\)\$')); // Split by $

    for (int i = 0; i < parts.length; i++) {
      if (i % 2 != 0) {
        // --- INLINE MATH ($x^2$) ---
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth * 0.90),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Math.tex(
                  parts[i],
                  mathStyle: MathStyle.text,
                  textStyle: style.copyWith(fontWeight: FontWeight.w600),
                  onErrorFallback: (_) => Text("\$${parts[i]}\$",
                      style: style.copyWith(color: Colors.red)),
                ),
              ),
            ),
          ),
        ));
      } else {
        // --- BOLD PROCESSING (**Text**) ---
        spans.addAll(_parseBold(parts[i]));
      }
    }
    return spans;
  }

  // 🟢 3. STRICT BOLD PARSER
  // This looks ONLY for double stars (**).
  // It completely ignores single stars (*), so "A * B" remains safe.
  List<InlineSpan> _parseBold(String input) {
    List<InlineSpan> spans = [];
    final parts = input.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (i % 2 != 0) {
        // Odd index = Inside ** ** -> Make BOLD
        spans.add(TextSpan(
            text: parts[i],
            style: style.copyWith(fontWeight: FontWeight.w700) // Bold
        ));
      } else {
        // Even index = Normal text (including single * symbols)
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(text: parts[i]));
        }
      }
    }
    return spans;
  }
}

// ---------------------------------------------------------------------
// NATIVE MARKDOWN (Only used for Tables/Images)
// ---------------------------------------------------------------------
class _NativeMarkdown extends StatelessWidget {
  final String data;
  final Color textColor;
  final double devicePixelRatio;
  final TextStyle baseStyle;
  final bool selectable;

  const _NativeMarkdown({
    required this.data,
    required this.textColor,
    required this.devicePixelRatio,
    required this.baseStyle,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final String formattedData = data.replaceAll('\n', '  \n');

    return MarkdownBody(
      data: formattedData,
      selectable: selectable,
      fitContent: false,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
        blockSpacing: 12,
        listBullet: baseStyle,
        tableBody: baseStyle,
        tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ),
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [LatexSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      builders: {
        'latex_inline': _LatexBuilder(baseStyle: baseStyle, isBlock: false),
        'latex_block': _LatexBuilder(baseStyle: baseStyle, isBlock: true),
      },
      imageBuilder: (uri, _, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: CachedNetworkImage(
            imageUrl: uri.toString(),
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
          ),
        );
      },
    );
  }
}

// (Keep LatexSyntax and _LatexBuilder classes the same as previous)
class LatexSyntax extends md.InlineSyntax {
  LatexSyntax() : super(r'(\$\$[\s\S]*?\$\$)|(\$[^$]*\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0)!;
    final bool isBlock = raw.startsWith('\$\$');
    final content = raw.replaceAll('\$\$', '').replaceAll('\$', '');
    parser.addNode(md.Element.text(isBlock ? 'latex_block' : 'latex_inline', content));
    return true;
  }
}

class _LatexBuilder extends MarkdownElementBuilder {
  final bool isBlock;
  final TextStyle baseStyle;
  _LatexBuilder({required this.isBlock, required this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? _) {
    final math = Math.tex(
      element.textContent,
      mathStyle: isBlock ? MathStyle.display : MathStyle.text,
      textStyle: baseStyle.copyWith(
          fontSize: isBlock ? 18 : 16,
          fontWeight: FontWeight.w600
      ),
      onErrorFallback: (_) => Text(element.textContent, style: const TextStyle(color: Colors.red)),
    );
    if (isBlock) {
      return Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: math));
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: math);
  }
}