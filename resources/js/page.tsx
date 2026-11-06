// Page data and navigation for React islands inside server-rendered Wellout
// pages. It covers the small part of the former Inertia client API that the
// remaining React components use: usePage, Link, Head, router and useForm.
// Islands provide the page data; navigation and forms use ordinary URLs,
// fetch and the CSRF cookie.
import {
  createContext,
  createElement,
  forwardRef,
  useCallback,
  useContext,
  useRef,
  useState,
  type AnchorHTMLAttributes,
  type ReactNode,
} from 'react';

export interface PageData<T = Record<string, unknown>> {
  props: T;
  url: string;
  component: string;
}

const PageContext = createContext<PageData | null>(null);

export function PageProvider({ value, children }: { value: PageData; children: ReactNode }) {
  return createElement(PageContext.Provider, { value }, children);
}

export function usePage<T = Record<string, unknown>>(): PageData<T> {
  const page = useContext(PageContext);
  if (page) return page as PageData<T>;
  return {
    props: {} as T,
    url: `${window.location.pathname}${window.location.search}`,
    component: '',
  };
}

type LinkProps = AnchorHTMLAttributes<HTMLAnchorElement> & {
  preserveState?: boolean;
  preserveScroll?: boolean;
  replace?: boolean;
  only?: string[];
  method?: string;
  as?: string;
  data?: Record<string, unknown>;
};

export const Link = forwardRef<HTMLAnchorElement, LinkProps>(function Link(
  {
    preserveState: _state,
    preserveScroll: _scroll,
    replace: _replace,
    only: _only,
    method: _method,
    as: _as,
    data: _data,
    ...props
  },
  ref,
) {
  return <a ref={ref} {...props} />;
});

/** The server writes the document head; islands do not change it. */
export function Head(_props: { title?: string; children?: ReactNode }) {
  return null;
}

function csrfToken(): string {
  const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]*)/);
  return match ? decodeURIComponent(match[1]) : '';
}

function formData(data: unknown): FormData {
  if (data instanceof FormData) return data;
  const body = new FormData();
  const append = (key: string, value: unknown) => {
    if (value === undefined || value === null) return;
    if (value instanceof Blob) body.append(key, value);
    else if (Array.isArray(value))
      value.forEach((entry, index) => append(`${key}[${index}]`, entry));
    else if (typeof value === 'object') {
      for (const [name, entry] of Object.entries(value as Record<string, unknown>))
        append(`${key}[${name}]`, entry);
    } else body.append(key, typeof value === 'boolean' ? (value ? '1' : '0') : String(value));
  };
  for (const [key, value] of Object.entries((data || {}) as Record<string, unknown>))
    append(key, value);
  return body;
}

interface VisitOptions {
  onStart?: () => void;
  onSuccess?: () => void;
  onError?: (errors: Record<string, string>) => void;
  onFinish?: () => void;
  preserveState?: boolean;
  preserveScroll?: boolean;
  replace?: boolean;
}

type BeforeListener = (event: { preventDefault: () => void }) => void;
const beforeListeners = new Set<BeforeListener>();

function allowed(): boolean {
  let cancelled = false;
  for (const listener of beforeListeners) listener({ preventDefault: () => (cancelled = true) });
  return !cancelled;
}

async function submit(
  method: string,
  url: string,
  data: unknown,
  options: VisitOptions = {},
): Promise<Response | null> {
  if (!allowed()) return null;
  options.onStart?.();
  try {
    const body = formData(data);
    if (method !== 'post') body.set('_method', method.toUpperCase());
    const response = await fetch(url, {
      method: 'POST',
      body,
      credentials: 'same-origin',
      headers: { Accept: 'text/html', 'X-XSRF-TOKEN': csrfToken() },
    });
    if (response.ok || response.redirected) {
      options.onSuccess?.();
      window.location.assign(response.url || url);
    } else if ((response.headers.get('Content-Type') || '').includes('text/html')) {
      // Show the server's page for a failed submission, as a plain form post would.
      const html = await response.text();
      document.open();
      document.write(html);
      document.close();
    } else {
      options.onError?.({ form: response.statusText || 'The request failed.' });
    }
    return response;
  } finally {
    options.onFinish?.();
  }
}

export const router = {
  get(url: string, data: Record<string, unknown> = {}, _options: VisitOptions = {}) {
    if (!allowed()) return;
    const target = new URL(url, window.location.href);
    for (const [key, value] of Object.entries(data)) {
      if (value === undefined || value === null || value === '') target.searchParams.delete(key);
      else target.searchParams.set(key, String(value));
    }
    window.location.assign(target.href);
  },
  visit(url: string, options: VisitOptions & { method?: string; data?: unknown } = {}) {
    const method = (options.method || 'get').toLowerCase();
    if (method === 'get') router.get(url, (options.data || {}) as Record<string, unknown>);
    else void submit(method, url, options.data, options);
  },
  post(url: string, data: unknown = {}, options: VisitOptions = {}) {
    return submit('post', url, data, options);
  },
  put(url: string, data: unknown = {}, options: VisitOptions = {}) {
    return submit('put', url, data, options);
  },
  delete(url: string, options: VisitOptions = {}) {
    return submit('delete', url, {}, options);
  },
  reload() {
    window.location.reload();
  },
  on(event: string, listener: BeforeListener) {
    if (event !== 'before') return () => {};
    beforeListeners.add(listener);
    return () => {
      beforeListeners.delete(listener);
    };
  },
  replaceProp(_name: string, _value: unknown) {},
};

export function useForm<T extends Record<string, unknown>>(initial: T) {
  const [data, setValues] = useState<T>(initial);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [processing, setProcessing] = useState(false);
  const transformer = useRef<(values: T) => unknown>((values) => values);
  const setData = useCallback((key: keyof T | T, value?: unknown) => {
    if (typeof key === 'object') setValues(key as T);
    else setValues((previous) => ({ ...previous, [key]: value }));
  }, []);
  function send(method: string, url: string, options: VisitOptions = {}) {
    return submit(method, url, transformer.current(data), {
      ...options,
      onStart: () => {
        setProcessing(true);
        options.onStart?.();
      },
      onError: (found) => {
        setErrors(found);
        options.onError?.(found);
      },
      onFinish: () => {
        setProcessing(false);
        options.onFinish?.();
      },
    });
  }
  return {
    data,
    setData,
    errors,
    processing,
    setError: (key: string, message: string) =>
      setErrors((previous) => ({ ...previous, [key]: message })),
    clearErrors: () => setErrors({}),
    transform: (callback: (values: T) => unknown) => {
      transformer.current = callback;
    },
    reset: (...fields: (keyof T)[]) =>
      setValues((previous) => {
        if (!fields.length) return initial;
        const next = { ...previous };
        for (const field of fields) next[field] = initial[field];
        return next;
      }),
    post: (url: string, options?: VisitOptions) => send('post', url, options),
    put: (url: string, options?: VisitOptions) => send('put', url, options),
    delete: (url: string, options?: VisitOptions) => send('delete', url, options),
  };
}
