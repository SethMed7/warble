import { describe, expect, test } from "bun:test";
import { median, p95 } from "./stats";

describe("median", () => {
  test("odd n takes the middle value", () => {
    expect(median([3, 1, 2])).toBe(2);
  });
  test("even n averages the middle two (matches --bench-e2e)", () => {
    expect(median([4, 1, 3, 2])).toBe(2.5);
  });
  test("single value", () => {
    expect(median([42])).toBe(42);
  });
});

describe("p95 (nearest rank, matches --bench-e2e)", () => {
  test("1..100 → 95", () => {
    const xs = Array.from({ length: 100 }, (_, i) => i + 1);
    expect(p95(xs)).toBe(95);
  });
  test("n=10 → 10th value (ceil(9.5) = rank 10)", () => {
    const xs = Array.from({ length: 10 }, (_, i) => i + 1);
    expect(p95(xs)).toBe(10);
  });
  test("single value", () => {
    expect(p95([7])).toBe(7);
  });
});
