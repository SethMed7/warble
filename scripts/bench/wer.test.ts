import { describe, expect, test } from "bun:test";
import { wer, words } from "./wer";

describe("words (normalization)", () => {
  test("lowercases and strips punctuation", () => {
    expect(words("Hello, world!")).toEqual(["hello", "world"]);
  });
  test("keeps in-word apostrophes, drops stray ones", () => {
    expect(words("it's easy — 'tis")).toEqual(["it's", "easy", "tis"]);
  });
  test("does NOT equate numerals and number words", () => {
    expect(words("3 dogs")).toEqual(["3", "dogs"]);
    expect(words("three dogs")).toEqual(["three", "dogs"]);
  });
  test("empty and whitespace-only input", () => {
    expect(words("")).toEqual([]);
    expect(words("  \n ")).toEqual([]);
  });
});

describe("wer", () => {
  test("identical text scores 0", () => {
    const s = wer("the quick brown fox", "the quick brown fox");
    expect(s.wer).toBe(0);
    expect(s.errors).toBe(0);
    expect(s.n).toBe(4);
  });
  test("punctuation and case differences score 0", () => {
    expect(wer("It's easy to tell the depth of a well.", "it's easy to tell the depth of a well").wer).toBe(0);
  });
  test("a contraction difference is a real error (its ≠ it's)", () => {
    expect(wer("it's easy", "its easy").sub).toBe(1);
  });
  test("one substitution in four words = 0.25", () => {
    const s = wer("the quick brown fox", "the quick brown box");
    expect(s).toMatchObject({ sub: 1, del: 0, ins: 0, errors: 1, n: 4 });
    expect(s.wer).toBe(0.25);
  });
  test("one deletion", () => {
    const s = wer("the quick brown fox", "the brown fox");
    expect(s).toMatchObject({ sub: 0, del: 1, ins: 0, n: 4 });
  });
  test("one insertion", () => {
    const s = wer("the brown fox", "the very brown fox");
    expect(s).toMatchObject({ sub: 0, del: 0, ins: 1, n: 3 });
  });
  test("mixed S/D/I counted from a minimal alignment", () => {
    // ref: a b c d → hyp: a x d e = sub(b→x) + del(c) + ins(e) = 3 errors over N=4
    const s = wer("a b c d", "a x d e");
    expect(s.errors).toBe(3);
    expect(s.wer).toBe(0.75);
  });
  test("empty hypothesis = all deletions, WER 1", () => {
    const s = wer("four words in here", "");
    expect(s).toMatchObject({ del: 4, errors: 4, n: 4 });
    expect(s.wer).toBe(1);
  });
  test("empty reference guard", () => {
    expect(wer("", "").wer).toBe(0);
    expect(wer("", "phantom words").wer).toBe(1);
  });
  test("WER can exceed 1 on heavy insertion", () => {
    const s = wer("hi", "hi there you three");
    expect(s.wer).toBeGreaterThan(1);
  });
});
