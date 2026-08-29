import "@testing-library/jest-dom/vitest"
import { cleanup } from "@testing-library/react"
import { afterEach } from "vitest"

afterEach(() => cleanup())

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

class IntersectionObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
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
