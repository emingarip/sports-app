declare global {
  interface Window {
    MiniGameBridge?: {
      postMessage: (message: string) => void;
    };
  }
}

function getReferrerOrigin(): string | null {
  if (!document.referrer) return null;
  try {
    return new URL(document.referrer).origin;
  } catch {
    return null;
  }
}

/** Hosts allowed to exchange auth messages with a game frame. */
const TRUSTED_ORIGINS = ['https://boskale.com', 'https://www.boskale.com'];

/** Loopback hosts, accepted only in a dev build. */
const DEV_HOSTS = ['localhost', '127.0.0.1', '[::1]'];

function isDevOrigin(origin: string): boolean {
  if (!import.meta.env.DEV) return false;
  try {
    return DEV_HOSTS.includes(new URL(origin).hostname);
  } catch {
    return false;
  }
}

export function isTrustedHostOrigin(origin: string): boolean {
  if (!origin) return false;
  if (origin === window.location.origin) return true;
  if (TRUSTED_ORIGINS.includes(origin)) return true;

  const referrerOrigin = getReferrerOrigin();
  if (referrerOrigin && origin === referrerOrigin) return true;

  // Was `origin.includes('localhost')`, which trusts
  // https://localhost.saldirgan.com - an attacker can register that. Hostname
  // is now matched exactly, and only in a dev build.
  return isDevOrigin(origin);
}

export function postMessageToHost(payload: string): void {
  if (window.MiniGameBridge) {
    window.MiniGameBridge.postMessage(payload);
  }

  const targetOrigin = getReferrerOrigin() ?? window.location.origin;

  if (window.parent && window.parent !== window) {
    window.parent.postMessage(payload, targetOrigin);
  }

  if (window.top && window.top !== window && window.top !== window.parent) {
    window.top.postMessage(payload, targetOrigin);
  }
}
