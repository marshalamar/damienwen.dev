import assert from "node:assert/strict";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

function essayPathsFrom(html) {
  return [
    ...new Set(
      [...html.matchAll(/href="(\/essays\/[a-z0-9-]+)"/g)].map(
        (match) => match[1],
      ),
    ),
  ];
}

test("renders the essay index", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html[^>]*lang="zh-CN"/i);
  assert.match(html, /Objects/);
  assert.match(html, /Echoes/);
  assert.match(html, /Damien/);
  assert.match(html, /Wen/);
  assert.match(html, /Music, Memory/);
  assert.match(html, /我想把听过的音乐记下来/);
  assert.match(html, /一张听歌小票/);
  assert.match(html, /读不完的 Skill/);
  assert.match(html, /无之场，场所逻辑下的agent Harness/);
  assert.match(html, /2026\.07\.26/);
  assert.match(html, /2026\.07\.28/);
  assert.match(html, /2026\.07\.29/);
  assert.match(html, /2026\.08\.03/);
  assert.deepEqual(essayPathsFrom(html), [
    "/essays/basho-harness",
    "/essays/unreadably-large-skill",
    "/essays/music-receipt",
    "/essays/rama-pi-extension",
  ]);
  assert.doesNotMatch(
    html,
    /这里记录我怎样|两篇关于音乐产品的思考|SHANGHAI|BY DAMIEN WEN|DAMIEN WEN · BEIJING|BEIJING · CHINA|BEIJING · MMXXVI/,
  );
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
  assert.doesNotMatch(
    html,
    /fonts\.googleapis\.com|fontsapi\.zeoseven\.com|cdn\.jsdelivr\.net/,
  );
  assert.match(html, /\/fonts\/zhuque\/result\.css/);
});

test("renders every essay linked from the index", async () => {
  const index = await render();
  const indexHtml = await index.text();
  const essayPaths = essayPathsFrom(indexHtml);

  assert.ok(essayPaths.length > 0, "the index should link to at least one essay");

  const renderedEssays = new Map();

  for (const essayPath of essayPaths) {
    const response = await render(essayPath);
    assert.equal(response.status, 200, `${essayPath} should render`);

    const html = await response.text();
    assert.match(html, /<article class="article">/);
    assert.match(html, /class="article-body"/);
    renderedEssays.set(essayPath, html);
  }

  const ramaHtml = renderedEssays.get("/essays/rama-pi-extension");
  const receiptHtml = renderedEssays.get("/essays/music-receipt");
  const skillHtml = renderedEssays.get("/essays/unreadably-large-skill");
  const bashoHtml = renderedEssays.get("/essays/basho-harness");

  assert.ok(ramaHtml, "the RAMA essay should remain linked");
  assert.ok(receiptHtml, "the Music Receipt essay should remain linked");
  assert.ok(skillHtml, "the Skill / Harness essay should remain linked");
  assert.ok(bashoHtml, "the basho / harness essay should remain linked");

  assert.match(ramaHtml, /从记忆里再找下一张专辑/);
  assert.match(ramaHtml, /Rate Your Music（RYM）/);
  assert.match(ramaHtml, /记忆留在本地/);
  assert.match(ramaHtml, /essay-sketch/);
  assert.match(ramaHtml, /DUAL MEMORY/);
  assert.match(ramaHtml, /RECOMMEND LOOP/);
  assert.match(ramaHtml, /LOCAL STORE/);
  assert.doesNotMatch(ramaHtml, /五分钟检查一次，一小时最多问一次/);
  assert.match(receiptHtml, /为什么是小票/);
  assert.match(receiptHtml, /生成以后就拿走/);
  assert.match(receiptHtml, /article-image/);
  assert.match(receiptHtml, /essays\/music-receipt\/music-receipt\.png/);
  assert.match(receiptHtml, /alt="[^"]+"/);
  assert.match(receiptHtml, /decoding="async"/);
  assert.match(receiptHtml, /height="1742"/);
  assert.match(receiptHtml, /loading="lazy"/);
  assert.match(receiptHtml, /width="640"/);
  assert.doesNotMatch(receiptHtml, /architecture--receipt/);
  assert.doesNotMatch(receiptHtml, /有几件事我会重做/);
  assert.match(skillHtml, /从体量膨胀看 Harness 存在的必要性/);
  assert.match(skillHtml, /审查能力没有跟着涨/);
  assert.match(skillHtml, /往里加提醒走不通/);
  assert.match(skillHtml, /确定性只剩 Harness/);
  assert.match(skillHtml, /essay-sketch/);
  assert.match(skillHtml, /VOLUME GAP/);
  assert.match(skillHtml, /SAME MATERIAL/);
  assert.match(skillHtml, /HARNESS BOUNDARY/);
  assert.match(bashoHtml, /包含停在绝对无/);
  assert.match(bashoHtml, /模型是有，harness 是无/);
  assert.match(bashoHtml, /作用是腾空/);
  assert.match(bashoHtml, /互相成就/);
  assert.match(bashoHtml, /essay-sketch/);
  assert.match(bashoHtml, /PLACE CHAIN/);
  assert.match(bashoHtml, /BEING \/ NOTHING/);
  assert.match(bashoHtml, /CO-CONSTITUTION/);
  assert.doesNotMatch(
    ramaHtml,
    /音乐产品不一定还缺一个更强的推荐算法|一个好用的主动 Agent/,
  );
  assert.doesNotMatch(
    receiptHtml,
    /产品感不等于功能多|可分享物，本身就是分发渠道/,
  );
});
