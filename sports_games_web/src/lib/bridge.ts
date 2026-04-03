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
  } catch (_) {
    return null;
  }
}

export function isTrustedHostOrigin(origin: string): boolean {
  if (!origin) return false;
  if (origin === window.location.origin) return true;

  const referrerOrigin = getReferrerOrigin();
  if (referrerOrigin && origin === referrerOrigin) return true;

  return origin.includes('localhost') || origin.includes('127.0.0.1');
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
