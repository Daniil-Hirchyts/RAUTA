export function AnimatedNumber({ value }: { value: number }) {
  const characters = String(value).split("")

  return (
    <span
      aria-label={String(value)}
      className="t-digit-group is-animating"
      key={value}
    >
      {characters.map((character, index) => (
        <span
          aria-hidden="true"
          className="t-digit"
          data-stagger={
            index === characters.length - 2
              ? "1"
              : index === characters.length - 1
                ? "2"
                : undefined
          }
          key={`${value}-${index}`}
        >
          {character}
        </span>
      ))}
    </span>
  )
}
