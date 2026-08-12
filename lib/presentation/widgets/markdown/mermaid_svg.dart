import 'dart:math' as math;

import 'package:xml/xml.dart';

/// Rewrites a Mermaid SVG into one a plain SVG renderer can draw.
///
/// Mermaid's output is written for a browser, and leans on two things Flutter's
/// SVG renderers do not implement:
///
/// 1. **A `<style>` sheet.** Colours live in class rules, and — this is the
///    part that bites — the elements often carry a *contradictory* presentation
///    attribute. A message line is literally `stroke="none"`, rescued only by
///    `.messageLine0{stroke:#333}`, because in CSS a stylesheet rule outranks a
///    presentation attribute. A renderer that ignores the sheet does not fall
///    back to something sensible; it draws nothing at all.
///
/// 2. **`<marker>` elements** for arrowheads, referenced by `marker-end`. No
///    Flutter renderer draws them, so every arrow loses its head.
///
/// Both are properties of the format rather than of any one diagram, so fixing
/// them here fixes every diagram type at once.
String flattenMermaidSvg(String svg) {
  final document = XmlDocument.parse(svg);
  final root = document.rootElement;

  final rules = _parseStylesheet(root);
  final markers = _collectMarkers(root);

  // The root is styled too, not just its descendants: the sheet's `#id` rule
  // sets the default fill that text inherits, and the root is where the
  // background hides.
  _paintBackground(root);

  for (final element in [root, ...root.descendantElements].toList()) {
    _applyComputedStyle(element, rules);
  }

  // Before the pass below, which folds these coordinates into the spans.
  _centreNoteText(root);

  // Needs the font sizes the pass above just resolved.
  for (final element in root.descendantElements.toList()) {
    _resolveTextOffsets(element);
  }

  // Arrowheads need the stroke colour resolved above.
  for (final element in root.descendantElements.toList()) {
    _bakeMarkers(element, markers);
  }

  return document.toXmlString();
}

// ── the stylesheet ──────────────────────────────────────────────────────────

/// One compound selector: `rect.actor`, `#merman`, `path`.
class _Compound {
  _Compound({required this.id, required this.classNames, required this.tag});

  final String? id;
  final Set<String> classNames;
  final String? tag;

  bool get isEmpty => id == null && tag == null && classNames.isEmpty;

  int get specificity =>
      (id != null ? 100 : 0) + classNames.length * 10 + (tag != null ? 1 : 0);

  bool matches(XmlElement element) {
    if (id != null && element.getAttribute('id') != id) return false;
    if (tag != null && element.localName != tag) return false;
    if (classNames.isEmpty) return true;

    final classes = (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toSet();
    return classes.containsAll(classNames);
  }
}

/// One `selector { declarations }` pair, matched against the real ancestry.
///
/// Ancestors are checked rather than dropped, and that is not fussiness:
/// `#merman .root .anchor path{fill:#333!important}` means a path inside an
/// anchor. Matching on the tail alone turned it into a rule for *every* path,
/// and being `!important` it then beat `.flowchart-link{fill:none}` — so every
/// edge in every flowchart was flood-filled black.
class _Rule {
  _Rule({
    required this.chain,
    required this.combinators,
    required this.order,
    required this.declarations,
  });

  /// Compounds left to right; the last one describes the element itself.
  final List<_Compound> chain;

  /// `combinators[i]` joins `chain[i]` to `chain[i + 1]`.
  final List<String> combinators;

  final int order;
  final Map<String, String> declarations;

  int get specificity =>
      chain.fold(0, (sum, compound) => sum + compound.specificity);

  bool matches(XmlElement element) {
    if (!chain.last.matches(element)) return false;

    var ancestor = element.parent;
    for (var i = chain.length - 2; i >= 0; i--) {
      final compound = chain[i];

      if (combinators[i] == '>') {
        if (ancestor is! XmlElement || !compound.matches(ancestor)) return false;
        ancestor = ancestor.parent;
        continue;
      }

      // Descendant: any ancestor will do, so climb until one fits.
      while (ancestor is XmlElement && !compound.matches(ancestor)) {
        ancestor = ancestor.parent;
      }
      if (ancestor is! XmlElement) return false;
      ancestor = ancestor.parent;
    }

    return true;
  }
}

_Compound _parseCompound(String text) {
  return _Compound(
    id: RegExp(r'#([A-Za-z0-9_-]+)').firstMatch(text)?.group(1),
    classNames: RegExp(r'\.([A-Za-z0-9_-]+)')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toSet(),
    tag: RegExp(r'^([a-zA-Z][a-zA-Z0-9]*)').firstMatch(text)?.group(1),
  );
}

List<_Rule> _parseStylesheet(XmlElement root) {
  final styles = root.descendantElements.where((e) => e.localName == 'style');
  if (styles.isEmpty) return const [];

  final rules = <_Rule>[];
  var order = 0;

  for (final style in styles.toList()) {
    final css = style.innerText;

    for (final match
        in RegExp(r'([^{}]+)\{([^}]*)\}', multiLine: true).allMatches(css)) {
      final declarations = _parseDeclarations(match.group(2)!);
      if (declarations.isEmpty) continue;

      // `a, b { … }` is one rule per selector.
      for (final selector in match.group(1)!.split(',')) {
        final trimmed = selector.trim();
        if (trimmed.isEmpty) continue;

        // Sibling combinators are not supported; skipping such a rule is
        // safer than applying it to the wrong element.
        if (trimmed.contains('+') || trimmed.contains('~')) continue;

        final parts = trimmed
            .replaceAll('>', ' > ')
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();

        final chain = <_Compound>[];
        final combinators = <String>[];
        for (final part in parts) {
          if (part == '>') {
            if (chain.isEmpty) break;
            combinators.add('>');
            continue;
          }
          if (chain.isNotEmpty && combinators.length < chain.length) {
            combinators.add(' ');
          }
          chain.add(_parseCompound(part));
        }

        if (chain.isEmpty || chain.last.isEmpty) continue;
        if (combinators.length != chain.length - 1) continue;

        rules.add(_Rule(
          chain: chain,
          combinators: combinators,
          order: order++,
          declarations: declarations,
        ));
      }
    }

    // The sheet has done its job; leaving it in would only invite a future
    // renderer to apply it twice.
    style.parent?.children.remove(style);
  }

  return rules;
}

Map<String, String> _parseDeclarations(String body) {
  final out = <String, String>{};
  for (final part in body.split(';')) {
    final index = part.indexOf(':');
    if (index <= 0) continue;
    final property = part.substring(0, index).trim().toLowerCase();
    final value = part.substring(index + 1).trim();
    if (property.isEmpty || value.isEmpty) continue;
    // `revert`, `unset` and friends are CSS cascade keywords with no SVG
    // meaning. Written out as attributes they are simply invalid paint —
    // stroke="revert" is not a colour.
    if (const {'revert', 'unset', 'initial', 'inherit', 'revert-layer'}
        .contains(value.toLowerCase())) {
      continue;
    }
    out[property] = value;
  }
  return out;
}

/// Properties worth moving onto the element. Layout and font properties are
/// left alone; this is about the things that decide whether a shape is visible.
const _paintProperties = {
  'fill',
  'stroke',
  'stroke-width',
  'stroke-dasharray',
  'stroke-linecap',
  'stroke-linejoin',
  'fill-opacity',
  'stroke-opacity',
  'opacity',
  'font-family',
  'font-size',
  'font-weight',
  'font-style',
  'text-anchor',
};

/// Resolves an element's paint the way a browser would, and writes the answer
/// back as presentation attributes.
///
/// Precedence, weakest first: presentation attribute, stylesheet rule, the
/// element's own `style=""`, anything flagged `!important`. Getting this order
/// wrong is not cosmetic — a line that says `stroke="none"` and is rescued by a
/// rule needs the rule to win, or it stays invisible.
void _applyComputedStyle(XmlElement element, List<_Rule> rules) {
  if (rules.isEmpty) return;

  final matched = rules.where((r) => r.matches(element)).toList()
    ..sort((a, b) => a.specificity != b.specificity
        ? a.specificity.compareTo(b.specificity)
        : a.order.compareTo(b.order));

  final computed = <String, String>{};
  final important = <String, String>{};

  for (final rule in matched) {
    rule.declarations.forEach((property, value) {
      if (!_paintProperties.contains(property)) return;
      if (value.contains('!important')) {
        important[property] = value.replaceAll('!important', '').trim();
      } else {
        computed[property] = value;
      }
    });
  }

  // The element's own inline style outranks the sheet.
  final inline = _parseDeclarations(element.getAttribute('style') ?? '');
  inline.forEach((property, value) {
    if (!_paintProperties.contains(property)) return;
    if (value.contains('!important')) {
      important[property] = value.replaceAll('!important', '').trim();
    } else {
      computed[property] = value;
    }
  });

  computed.addAll(important);
  if (computed.isEmpty) return;

  computed.forEach((property, value) {
    element.setAttribute(property, value);
  });

  // Written as attributes now, so the style attribute would be a second source
  // of truth for the same thing.
  if (element.getAttribute('style') != null) {
    element.removeAttribute('style');
  }
}

// ── arrowheads ──────────────────────────────────────────────────────────────

class _Marker {
  _Marker({required this.refX, required this.refY, required this.children});

  final double refX;
  final double refY;
  final List<XmlNode> children;
}

Map<String, _Marker> _collectMarkers(XmlElement root) {
  final markers = <String, _Marker>{};

  for (final element in root.descendantElements.toList()) {
    if (element.localName != 'marker') continue;
    final id = element.getAttribute('id');
    if (id == null) continue;

    markers[id] = _Marker(
      refX: double.tryParse(element.getAttribute('refX') ?? '') ?? 0,
      refY: double.tryParse(element.getAttribute('refY') ?? '') ?? 0,
      children: element.children.map((c) => c.copy()).toList(),
    );
  }

  return markers;
}

/// Draws the arrowhead that `marker-end` only referenced.
///
/// The marker's own geometry is reused rather than approximated with a triangle
/// of our own: the shapes differ per arrow kind — a filled head, an open cross,
/// a hollow tip — and inventing one would quietly change what an arrow means.
void _bakeMarkers(XmlElement element, Map<String, _Marker> markers) {
  final reference = element.getAttribute('marker-end');
  if (reference == null) return;

  element.removeAttribute('marker-end');

  final id = RegExp(r'url\(#([^)]+)\)').firstMatch(reference)?.group(1);
  final marker = markers[id];
  if (marker == null) return;

  final tip = _endOf(element);
  if (tip == null) return;

  final degrees = tip.angle * 180 / math.pi;
  final paint = element.getAttribute('stroke');

  final group = XmlElement(XmlName('g'), [
    XmlAttribute(
      XmlName('transform'),
      'translate(${_n(tip.x)},${_n(tip.y)}) rotate(${_n(degrees)}) '
      'translate(${_n(-marker.refX)},${_n(-marker.refY)})',
    ),
    // Markers inherit no paint of their own here, so the head takes the colour
    // of the line it terminates. Without this it falls back to black and a
    // pale arrow gains a dark tip.
    if (paint != null && paint != 'none') XmlAttribute(XmlName('fill'), paint),
  ], marker.children.map((c) => c.copy()));

  final parent = element.parent;
  if (parent == null) return;
  parent.children.insert(parent.children.indexOf(element) + 1, group);
}

class _Tip {
  const _Tip(this.x, this.y, this.angle);
  final double x;
  final double y;
  final double angle;
}

/// Where a shape ends, and which way it was heading when it got there.
_Tip? _endOf(XmlElement element) {
  double? number(String name) =>
      double.tryParse(element.getAttribute(name) ?? '');

  if (element.localName == 'line') {
    final x1 = number('x1'), y1 = number('y1');
    final x2 = number('x2'), y2 = number('y2');
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    return _Tip(x2, y2, math.atan2(y2 - y1, x2 - x1));
  }

  if (element.localName == 'path') {
    return _endOfPath(element.getAttribute('d') ?? '');
  }

  return null;
}

/// The last point of a path, and the direction of approach.
///
/// Only the coordinates matter, so commands are reduced to the points they
/// carry: the tangent of a curve at its end runs from its final control point
/// to its endpoint, which is exactly the last two points in the stream.
_Tip? _endOfPath(String d) {
  if (d.isEmpty) return null;

  final numbers = RegExp(r'-?\d*\.?\d+(?:e[-+]?\d+)?', caseSensitive: false)
      .allMatches(d)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  if (numbers.length < 4) return null;

  final endX = numbers[numbers.length - 2];
  final endY = numbers[numbers.length - 1];
  final priorX = numbers[numbers.length - 4];
  final priorY = numbers[numbers.length - 3];

  // A zero-length final segment has no direction to report; walking further
  // back would be guesswork, so the head is left off rather than pointed the
  // wrong way.
  if (endX == priorX && endY == priorY) return null;

  return _Tip(endX, endY, math.atan2(endY - priorY, endX - priorX));
}

/// Trims the float noise that would otherwise triple the size of a transform.
String _n(double value) {
  final rounded = value.toStringAsFixed(2);
  return rounded.endsWith('.00')
      ? rounded.substring(0, rounded.length - 3)
      : rounded;
}

// ── the background ──────────────────────────────────────────────────────────

/// Drops the root's `background-color`, without replacing it.
///
/// SVG has no background property; `background-color` on the root is CSS,
/// which a browser honours and a plain SVG renderer ignores. Removing it is
/// therefore cosmetic here — but it is removed rather than left, so a renderer
/// that *does* honour it cannot paint a slab the app never asked for.
///
/// Nothing is painted in its place on purpose: the diagram sits inside the
/// block's own card, which already provides the ground, the border and the
/// rounded corners. A second opaque rectangle inside that card reads as a hard
/// slab with square corners over a translucent panel.
void _paintBackground(XmlElement root) {
  final style = root.getAttribute('style');
  if (style == null) return;

  final declarations = _parseDeclarations(style)..remove('background-color');

  final remaining =
      declarations.entries.map((e) => '${e.key}:${e.value}').join(';');
  if (remaining.isEmpty) {
    root.removeAttribute('style');
  } else {
    root.setAttribute('style', remaining);
  }
}

/// Turns `dy` line advances into explicit coordinates.
///
/// Mermaid places label lines relatively: the `<text>` carries no `y` at all
/// and each `<tspan>` says `dy="1em"`, so a renderer that ignores `dy` draws
/// every line at the group's origin. That is why branch labels sat above their
/// own boxes instead of inside them.
///
/// Relative offsets are accumulated into an absolute `y` per line, which needs
/// no support beyond plain coordinates.
void _resolveTextOffsets(XmlElement element) {
  if (element.localName != 'text') return;

  final spans =
      element.childElements.where((c) => c.localName == 'tspan').toList();
  if (spans.isEmpty) return;

  final fontSize = _fontSizeFor(element);
  final baseX = double.tryParse(element.getAttribute('x') ?? '') ?? 0;
  final shift = _baselineShift(element, fontSize);
  var y = double.tryParse(element.getAttribute('y') ?? '') ?? 0;

  for (final span in spans) {
    y += _lengthOf(span.getAttribute('dy'), fontSize);
    final x = baseX + _lengthOf(span.getAttribute('dx'), fontSize);

    // An explicit x already on the span wins; it is absolute, not an offset.
    span.setAttribute('x', _n(double.tryParse(span.getAttribute('x') ?? '') ?? x));
    span.setAttribute('y', _n(y + shift));
    span.removeAttribute('dy');
    span.removeAttribute('dx');
  }

  // Consumed into the coordinates above; leaving them invites a renderer that
  // *does* honour them to apply the same shift twice.
  element.removeAttribute('dominant-baseline');
  element.removeAttribute('alignment-baseline');
}

/// How far to move a baseline so the text sits where the box expects it.
///
/// `dominant-baseline="middle"` asks for the text to be centred on its `y`.
/// Ignored, that `y` is read as the baseline instead and the glyphs ride up
/// above it — which is why the first line of a note box was clipped by its own
/// top edge. There is no exact answer without font metrics; 0.35em is the
/// usual stand-in for half the x-height.
double _baselineShift(XmlElement element, double fontSize) {
  final baseline = element.getAttribute('dominant-baseline') ??
      element.getAttribute('alignment-baseline');

  switch (baseline) {
    case 'middle':
    case 'central':
      return fontSize * 0.35;
    case 'hanging':
    case 'text-before-edge':
      return fontSize * 0.8;
    case 'text-after-edge':
    case 'ideographic':
      return -fontSize * 0.2;
    default:
      return 0;
  }
}

/// The font size in effect, inherited from the nearest ancestor that names one.
double _fontSizeFor(XmlElement element) {
  XmlNode? node = element;
  while (node is XmlElement) {
    final declared = node.getAttribute('font-size');
    if (declared != null) {
      final size = double.tryParse(declared.replaceAll(RegExp(r'[a-z%]+$'), ''));
      if (size != null && size > 0) return size;
    }
    node = node.parent;
  }
  return 16;
}

/// A CSS length in user units. `em` is the only relative unit Mermaid emits.
double _lengthOf(String? raw, double fontSize) {
  if (raw == null || raw.isEmpty) return 0;
  final value =
      double.tryParse(raw.replaceAll(RegExp(r'(em|px|pt)$'), '').trim());
  if (value == null) return 0;
  return raw.endsWith('em') ? value * fontSize : value;
}


// ── note boxes ──────────────────────────────────────────────────────────────

/// Centres a note's text inside the box drawn for it.
///
/// Merman sizes a note box with more padding than its text block occupies and
/// then places the text from the top, so the lines sit high in the box with
/// empty space beneath them and the first one grazing the top border. The
/// coordinates disagree with each other at the source; nothing downstream can
/// infer the intent.
///
/// The pairing is not guessed from geometry — mermaid labels the parts, `note`
/// on the box and `noteText` on each line, so a box is matched to its own text
/// and to nothing else.
void _centreNoteText(XmlElement root) {
  final elements = root.descendantElements.toList();

  bool hasClass(XmlElement e, String name) =>
      (e.getAttribute('class') ?? '').split(RegExp(r'\s+')).contains(name);

  final lines = elements.where((e) => hasClass(e, 'noteText')).toList();
  if (lines.isEmpty) return;

  for (final box in elements.where((e) => hasClass(e, 'note'))) {
    final x = double.tryParse(box.getAttribute('x') ?? '');
    final y = double.tryParse(box.getAttribute('y') ?? '');
    final width = double.tryParse(box.getAttribute('width') ?? '');
    final height = double.tryParse(box.getAttribute('height') ?? '');
    if (x == null || y == null || width == null || height == null) continue;

    // A note's own lines: horizontally within it, and vertically no further
    // out than a line's worth, which tolerates the overhang being corrected
    // without adopting a neighbouring note's text.
    final mine = lines.where((line) {
      final lx = double.tryParse(line.getAttribute('x') ?? '');
      final ly = double.tryParse(line.getAttribute('y') ?? '');
      if (lx == null || ly == null) return false;
      return lx >= x && lx <= x + width && ly >= y - height && ly <= y + height * 2;
    }).toList();
    if (mine.isEmpty) continue;

    final ys = mine
        .map((line) => double.parse(line.getAttribute('y')!))
        .toList()
      ..sort();
    final shift = (y + height / 2) - (ys.first + (ys.last - ys.first) / 2);
    if (shift.abs() < 0.5) continue;

    for (final line in mine) {
      line.setAttribute(
        'y',
        _n(double.parse(line.getAttribute('y')!) + shift),
      );
    }
  }
}
