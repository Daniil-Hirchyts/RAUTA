import "@testing-library/jest-dom/vitest"
import { cleanup } from "@testing-library/react"
import { afterEach, vi } from "vitest"

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

Object.defineProperty(navigator, "vibrate", {
  configurable: true,
  value: vi.fn(() => true),
})

const storage = new Map<string, string>()
const localStorageStub: Storage = {
  get length() {
    return storage.size
  },
  clear: () => storage.clear(),
  getItem: (key) => storage.get(key) ?? null,
  key: (index) => [...storage.keys()][index] ?? null,
  removeItem: (key) => {
    storage.delete(key)
  },
  setItem: (key, value) => {
    storage.set(key, String(value))
  },
}

Object.defineProperty(globalThis, "localStorage", {
  configurable: true,
  value: localStorageStub,
})

class ResizeObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
}

// Real observers so tests can simulate "the sentinel scrolled into view" —
// jsdom does no layout, so there's no geometry to trigger this for real.
const intersectionObservers: {
  callback: IntersectionObserverCallback
  elements: Set<Element>
}[] = []

class IntersectionObserverStub {
  callback: IntersectionObserverCallback
  elements = new Set<Element>()

  constructor(callback: IntersectionObserverCallback) {
    this.callback = callback
    intersectionObservers.push(this)
  }

  observe(element: Element) {
    this.elements.add(element)
  }

  unobserve(element: Element) {
    this.elements.delete(element)
  }

  disconnect() {
    this.elements.clear()
  }
}

/** Fires every IntersectionObserver currently watching `element` as if it
 *  had just scrolled into view. */
export function triggerIntersection(element: Element) {
  for (const observer of intersectionObservers) {
    if (!observer.elements.has(element)) continue
    observer.callback(
      [{ isIntersecting: true, target: element } as IntersectionObserverEntry],
      observer as unknown as IntersectionObserver
    )
  }
}

Object.defineProperty(window, "ResizeObserver", {
  configurable: true,
  value: ResizeObserverStub,
})

Object.defineProperty(window, "IntersectionObserver", {
  configurable: true,
  value: IntersectionObserverStub,
})

Object.defineProperty(window, "matchMedia", {
  configurable: true,
  value: () => ({
    matches: false,
    addEventListener() {},
    removeEventListener() {},
  }),
})

HTMLElement.prototype.scrollIntoView = () => {}
