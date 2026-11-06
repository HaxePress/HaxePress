// Enhances a form of server-rendered package settings (PackageSettingField).
import { enhancePackageFields } from '../package-fields';

export function mount(element: HTMLElement) {
  enhancePackageFields(element);
}
