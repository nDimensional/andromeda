// [a, b] -> [c, d]
export const map = (a: number, b: number, c: number, d: number, x: number) => ((d - c) * (x - a)) / (b - a) + c;
