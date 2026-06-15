import { describe, expect, test } from "bun:test";
import { cleaned } from "./clean";

describe("acceptance", () => {
  test("numeral correction via 'actually'", () => {
    expect(cleaned("give me 2 actually 3 bunnies")).toBe("give me 3 bunnies");
  });

  test("fillers and duplicate words", () => {
    expect(cleaned("um so like like I was thinking uh maybe we ship it"))
      .toBe("so like I was thinking maybe we ship it");
  });

  test("name correction via 'I mean'", () => {
    expect(cleaned("send it to John I mean Jane")).toBe("send it to Jane");
  });

  test("number-word correction via 'no wait'", () => {
    expect(cleaned("set a timer for five no wait ten minutes"))
      .toBe("set a timer for ten minutes");
  });

  test("'scratch that' drops the previous clause", () => {
    expect(cleaned("do the report scratch that do the deck")).toBe("do the deck");
  });
});

describe("fillers", () => {
  test("removes standalone fillers only", () => {
    expect(cleaned("uhh er hmm mhm okay erm ah done")).toBe("okay done");
  });

  test("does not eat words containing filler letters", () => {
    expect(cleaned("the umbrella is ahead")).toBe("the umbrella is ahead");
  });

  test("removes bare 'you know' set off by punctuation", () => {
    expect(cleaned("it was, you know, fine")).toBe("it was, fine");
  });

  test("removes dangling 'you know' at the end", () => {
    expect(cleaned("it was great you know")).toBe("it was great");
  });

  test("keeps 'you know' when it carries meaning", () => {
    expect(cleaned("you know the answer")).toBe("you know the answer");
  });
});

describe("corrections", () => {
  test("'wait no' between number words", () => {
    expect(cleaned("grab six wait no nine apples")).toBe("grab nine apples");
  });

  test("'make that' between number words", () => {
    expect(cleaned("give me two make that three")).toBe("give me three");
  });

  test("'rather' between plain tokens", () => {
    expect(cleaned("paint it blue rather green")).toBe("paint it green");
  });

  test("marker stays when shapes differ", () => {
    expect(cleaned("I actually like it")).toBe("I actually like it");
  });

  test("marker at the start stays", () => {
    expect(cleaned("actually let's go")).toBe("actually let's go");
  });

  test("'scratch that' respects sentence boundaries", () => {
    expect(cleaned("ship it today. do the report scratch that do the deck"))
      .toBe("ship it today. do the deck");
  });
});

describe("duplicates", () => {
  test("collapses immediate repeats case-insensitively", () => {
    expect(cleaned("the The cat")).toBe("the cat");
  });

  test("does not collapse across a sentence boundary", () => {
    expect(cleaned("stop. stop right there")).toBe("stop. stop right there");
  });
});

describe("tidy", () => {
  test("collapses whitespace and fixes space before punctuation", () => {
    expect(cleaned("  hello ,  world  !")).toBe("hello, world!");
  });

  test("capitalizes only when the raw text did", () => {
    expect(cleaned("Um hello there")).toBe("Hello there");
    expect(cleaned("um hello there")).toBe("hello there");
  });

  test("empty and filler-only input", () => {
    expect(cleaned("")).toBe("");
    expect(cleaned("um uh hmm")).toBe("");
  });
});
