export function titleCase(value: string) {
  return value.replace(/\b\w/g, (letter) => letter.toUpperCase())
}
