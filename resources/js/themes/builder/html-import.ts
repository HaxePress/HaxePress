import { htmlTags, newBlock, type DesignBlock, type StyleMap } from './types';
import type { MediaRules } from '../../media';

/** Parse inert HTML with the browser DOM, then validate the resulting document on the server. */
export function importHtml(
  source: string,
  rules?: MediaRules,
): { nodes: DesignBlock[]; css: string } {
  const template = document.createElement('template');
  template.innerHTML = source;
  const styles: string[] = [];
  let count = 0;
  function convert(node: Node): DesignBlock[] {
    if (++count > 2048) throw new Error('The imported HTML contains too many elements.');
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent || '';
      if (!text.trim()) return [];
      const element = newBlock('element');
      element.tag = 'span';
      element.text = text;
      return [element];
    }
    if (!(node instanceof Element)) return [];
    const tag = node.localName;
    if (tag === 'style') {
      styles.push(node.textContent || '');
      return [];
    }
    if (['script', 'iframe', 'object', 'embed', 'link', 'meta', 'base'].includes(tag)) return [];
    if (tag === 'title' && !node.closest('svg')) return [];
    if (tag === 'img') {
      const src = node.getAttribute('src') || '';
      if (src && (!rules || !new RegExp(rules.imagePattern).test(src)))
        throw new Error(
          'Imported images must already exist in the media library. Upload them and use their managed addresses.',
        );
      const image = newBlock('image');
      image.image = src;
      image.alt = node.getAttribute('alt') || '';
      copyAttributes(node, image);
      return [image];
    }
    const element = newBlock('element');
    element.tag = (htmlTags as readonly string[]).includes(tag) ? tag : 'div';
    element.name = node.getAttribute('data-name') || tag;
    copyAttributes(node, element);
    element.children = Array.from(node.childNodes).flatMap(convert);
    return [element];
  }
  function copyAttributes(element: Element, node: DesignBlock) {
    node.classes = Array.from(element.classList).filter((name) =>
      /^[A-Za-z_][A-Za-z0-9_:-]{0,79}$/.test(name),
    );
    node.attributes = {};
    for (const attribute of Array.from(element.attributes)) {
      if (
        ['class', 'style', 'src', 'srcset', 'alt', 'data-name'].includes(attribute.name) ||
        /^on/i.test(attribute.name)
      )
        continue;
      if (attribute.name === 'href') {
        node.href = attribute.value;
        continue;
      }
      // Only HTML element blocks take attributes; an imported image keeps its classes and styles.
      if (node.type === 'element') node.attributes[attribute.name] = attribute.value;
    }
    const style = (element as HTMLElement).style;
    if (style) {
      const values: StyleMap = {};
      for (const property of Array.from(style)) values[property] = style.getPropertyValue(property);
      node.styles = { desktop: { normal: values } };
    }
  }
  const nodes = Array.from(template.content.childNodes).flatMap(convert);
  if (!nodes.length) throw new Error('Add HTML elements to import.');
  return { nodes, css: styles.join('\n') };
}
