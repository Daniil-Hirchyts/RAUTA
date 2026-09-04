export function titleCase(value: string) {
  return value.replace(/\b\w/g, (letter) => letter.toUpperCase())
}

/** "1 workout", "3 workouts". The app counts things in a lot of places and
 *  they should all read the same way. */
export function countLabel(count: number, noun: string) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`
}
