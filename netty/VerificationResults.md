# 検証結果

## 検証方法
- `/slow` エンドポイント（10秒かかる処理）にリクエスト送信中にSIGTERMを送信
- リクエストが正常に完了（HTTP 200）すればグレースフルシャットダウン成功

## Ktor 3.0.3
`application.yaml` に `shutdownGracePeriod` / `shutdownTimeout` を設定することでグレースフルシャットダウンが有効になった。

```yaml
ktor:
  deployment:
    shutdownGracePeriod: 15000
    shutdownTimeout: 20000
```

| 設定 | 結果 |
|---|---|
| 設定なし（デフォルト） | リクエスト中断（グレースフルシャットダウン不可） |
| shutdownGracePeriod/Timeout設定あり | リクエスト正常完了（グレースフルシャットダウン成功） |

## Ktor 3.3.2
同じ `shutdownGracePeriod` / `shutdownTimeout` の設定では**グレースフルシャットダウンが効かなかった**。

| 設定 | 結果 |
|---|---|
| shutdownGracePeriod/Timeout設定あり | リクエスト中断（グレースフルシャットダウン不可） |

# 調査

## 調査方法
### ログ
- logback.xmlのログレベルをTRACEに変更（`io.ktor.server`, `io.ktor.server.engine`, `io.ktor.server.netty`）
- `immediateFlush=true` でバッファフラッシュの問題を排除
- Ktor 3.0.3版とKtor 3.3.2版の**両方**でSIGTERM送信時のログを取得し比較
- ログは成果物として `logs/` ディレクトリに保存

### その他の確認
- 公式ドキュメント
- GitHub issue / PR
- ソースコード比較（GitHubの各バージョンタグから取得）

### 分析
- 上記を総合的に判断（出揃う前に途中で結論を出さない）し、原因と対策を考える

---

## 調査結果

### ログ比較

Ktor 3.0.3とKtor 3.3.2の両方で同一条件（TRACEログ + immediateFlush）でログを取得した。

#### 結果

| 項目 | Ktor 3.0.3 | Ktor 3.3.2 |
|---|---|---|
| curlのHTTPステータス | **200**（正常完了） | **000**（コネクション切断） |
| SIGTERM〜curl完了 | 約8秒（リクエスト処理完了まで待機） | **約15ms**（即座に切断） |
| SIGTERM〜プロセス終了 | 約30秒（gracePeriod + timeout分待機） | 約20秒（timeout分待機） |
| シャットダウン関連のログ出力 | なし | なし |

ログファイル: `logs/shutdown-303.log`, `logs/shutdown-332.log`

#### 考察
- **両バージョンともシャットダウン関連のTRACEログは出力されなかった**。これはログ設定の問題ではなく、Ktorのシャットダウンコードパスにログ出力が実装されていないことを意味する
- 3.3.2ではSIGTERM送信から約15msでコネクションが切断されるが、プロセス自体は約20秒間生存する。これは `stop()` メソッド自体は呼ばれているが、**イベントグループのシャットダウン開始直後にクライアントコネクションが即座に切断されている**ことを示す

### System.out.printlnによるイベント追跡

TRACEログが出ないため、`System.out.println` でKtorライフサイクルイベントとJVMシャットダウンフックの発火タイミングを計測した。

#### Ktor 3.0.3 (`logs/shutdown-303-hooktest.log`)

| タイムスタンプ | イベント |
|---|---|
| T+0ms | JVM SHUTDOWN HOOK |
| T+0ms | ApplicationStopPreparing |
| T+30s | ApplicationStopping |
| T+30s | ApplicationStopped |

- curlは HTTP 200 を返した
- ApplicationStopPreparingからApplicationStoppingまで約30秒（gracePeriod + timeout）の猶予がある

#### Ktor 3.3.2 (`logs/shutdown-332-sysout.log`)

| タイムスタンプ | イベント |
|---|---|
| T+0ms | JVM SHUTDOWN HOOK |
| T+0ms | ApplicationStopPreparing |
| （イベントループ停止によりApplicationStopping/Stoppedが記録されず） |

- curlは HTTP 000 を返した（コネクション切断）
- 設定値の読み込みは正常（gracePeriod=15000, timeout=20000 を確認）
- シャットダウン中に `NoClassDefFoundError`（`AbstractChannelHandlerContext$4`, `ThrowableProxy`, `FreeChunkEvent`）が発生。該当クラスはfat JAR内に存在するため、JVMシャットダウン中のクラスローダーのタイミング問題と推定

### 代替仮説の消去テスト

グレースフルシャットダウン失敗の原因を切り分けるため、3.3.2で以下のテストを実施した。

| テスト | 内容 | 結果 | 結論 |
|---|---|---|---|
| embeddedServer | EngineMainの代わりにembeddedServerを使用 | 000（失敗） | EngineMain固有の問題ではない |
| mvn exec:java | shade JAR ではなくmvn exec:javaで実行 | 000（失敗） | fat JARのパッケージング問題ではない |
| Thread.sleep | `delay(10000)` を `Thread.sleep(10000)` に変更 | 000（失敗） | コルーチンのキャンセル問題ではない |
| ShutdownHook=false | `ShutdownHook`を無効化し、メインスレッドからのみstop()を呼ぶ | 000（失敗） | 二重stop()の競合問題ではない |
| wait=false + join | `start(wait=false)` + `Thread.currentThread().join()` でメインスレッドからのstop()を回避 | 000（失敗） | 二重stop()の競合問題ではない（再確認） |

すべてのテストで失敗したことから、問題はアプリケーション層ではなく `NettyApplicationEngine.stop()` 内部のNettyイベントグループのシャットダウンメカニズムにあることが確定した。

### 3.4.0でも未解決の確認

Ktor 3.4.0（PR #5230で`stop()`が再設計）でも同一テスト条件でHTTP 000が返り、グレースフルシャットダウンが機能しないことを確認した。

### GitHub issue / PR 調査

Ktor 3.0.3〜3.4.0 の間で、シャットダウン関連の多数のバグ修正・変更が行われていた。

#### 主要な変更の時系列

| バージョン | issue / PR | 内容 |
|---|---|---|
| 3.2.0 | [KTOR-8291](https://github.com/ktorio/ktor/pull/4761) | `Application.dispose()` → `Application.disposeAndJoin()` に変更。アプリケーションの子コルーチンをjoinするように |
| 3.2.0 | [PR #4828](https://github.com/ktorio/ktor/pull/4828) | CIOエンジンのグレースフルシャットダウン修正（CIOのみ） |
| 3.3.1 | [KTOR-8771](https://github.com/ktorio/ktor/pull/5089) | `EmbeddedServer.stop()` で `shutdownTimeout` の代わりに `shutdownGracePeriod` が使われていたバグを修正 |
| 3.3.1 | [KTOR-8770](https://github.com/ktorio/ktor/pull/5102) | Nettyで `shutdownGracePeriod` の2倍の時間ブロックしていたバグを修正。**`shutdownConnections.await()` の位置を変更** |
| 3.3.3 | [KTOR-8671](https://github.com/ktorio/ktor/pull/5183) | Nettyシャットダウン時の`RejectedExecutionException`レースコンディション修正（不完全な修正） |
| 3.4.0 | [KTOR-8671](https://github.com/ktorio/ktor/pull/5230) | 上記の完全な修正。シャットダウン順序を再修正（ただしグレースフルシャットダウンの問題は未解決） |

※ PR #5183のマージ日（2025-11-24）はKtor 3.3.2のリリース日（2025-11-05）より後であるため、3.3.2には含まれず3.3.3（2025-11-27リリース）に含まれる。同様にPR #5230（マージ: 2025-12-09）は3.4.0（2026-01-23リリース）に含まれる。

### ソースコード比較

`NettyApplicationEngine.stop()` の実装をGitHubの各バージョンタグから取得して比較した。

#### Ktor 3.0.3（正常動作）
```kotlin
override fun stop(gracePeriodMillis: Long, timeoutMillis: Long) {
    cancellationJob?.complete()
    monitor.raise(ApplicationStopPreparing, environment)
    val channelFutures = channels?.mapNotNull { if (it.isOpen) it.close() else null }.orEmpty()

    try {
        val shutdownConnections =
            connectionEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
        shutdownConnections.await() // ★ connectionのシャットダウン完了を先に待つ

        val shutdownWorkers =
            workerEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
        if (configuration.shareWorkGroup) {
            shutdownWorkers.await()
        } else {
            val shutdownCall =
                callEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
            shutdownWorkers.await()
            shutdownCall.await()
        }
    } finally {
        channelFutures.forEach { it.sync() }
    }
}
```

#### Ktor 3.3.2（グレースフルシャットダウン不可）
```kotlin
override fun stop(gracePeriodMillis: Long, timeoutMillis: Long) {
    cancellationJob?.complete()
    monitor.raise(ApplicationStopPreparing, environment)
    val channelFutures = channels?.mapNotNull { if (it.isOpen) it.close() else null }.orEmpty()

    try {
        val shutdownConnections =
            connectionEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
        // ★ shutdownConnections.await() がここにない — 全グループが同時にシャットダウン開始
        val shutdownWorkers =
            workerEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
        if (configuration.shareWorkGroup) {
            shutdownWorkers.await()
        } else {
            val shutdownCall =
                callEventGroup.shutdownGracefully(gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS)
            shutdownWorkers.await()
            shutdownCall.await()
        }
        shutdownConnections.await() // ★ connectionのawaitが最後に移動
    } finally {
        channelFutures.forEach { it.sync() }
    }
}
```

この変更はKTOR-8770（PR #5102、3.3.1）で導入された。元々は `shutdownConnections.await()` が先にブロックし、その後worker/callのシャットダウンでも再度ブロックすることで、合計待ち時間が `2 × shutdownGracePeriod` になる問題を修正する目的だった。

#### Ktor 3.4.0の `stop()` （[PR #5230](https://github.com/ktorio/ktor/pull/5230)）
```kotlin
// クラス: io.ktor.server.netty.NettyApplicationEngine
// 3つのNetty EventLoopGroupを持つ:
//   - connectionEventGroup: 新規TCP接続の受付（Nettyのboss相当）
//   - workerEventGroup:     HTTP処理。クライアントコネクションのチャネルが登録されている
//   - callEventGroup:       Ktorアプリケーションロジック（routingハンドラ等）の実行

override fun stop(gracePeriodMillis: Long, timeoutMillis: Long) {
    // アプリケーションのキャンセルを通知（コルーチンの協調的キャンセル用）
    cancellationJob?.complete()
    // リスナーにシャットダウン準備開始を通知
    monitor.raise(ApplicationStopPreparing, environment)

    // ── ステップ1: サーバーチャネル（リスニングソケット）を同期的にクローズ ──
    // 新規TCP接続の受付を停止する。所要時間を記録して後続のtimeout計算に使う
    val channelsCloseTime = measureTimeMillis {
        val channelFutures = channels?.mapNotNull { if (it.isOpen) it.close() else null }.orEmpty()
        channelFutures.forEach { future ->
            withStopException { future.sync() }
        }
    }

    val noQuietPeriod = 0L
    // ステップ1の所要時間を差し引いてtimeoutを再計算（gracePeriod以上を保証）
    val timeoutMillis = (timeoutMillis - channelsCloseTime).coerceAtLeast(gracePeriodMillis)

    // ── ステップ2: connection と worker を同時にシャットダウン開始 ──

    // connectionEventGroup: quietPeriod=0 で新規接続の受付を即座に停止
    val shutdownConnections = connectionEventGroup.shutdownGracefully(
        noQuietPeriod, timeoutMillis, TimeUnit.MILLISECONDS
    )
    // ★ workerEventGroup: quietPeriod=gracePeriodMillis でインフライトリクエストの保護を意図
    //   しかし Netty の shutdownGracefully() は呼び出し直後に isShuttingDown()=true となり、
    //   次のイベントループ反復で closeAll() が実行され、登録されている全チャネル
    //   （＝クライアントコネクション）が即座にクローズされる。
    //   quietPeriod はイベントループスレッドの終了を遅延させるだけで、
    //   チャネルのクローズは防げない。← ★ グレースフルシャットダウンが効かない根本原因
    val shutdownWorkers = workerEventGroup.shutdownGracefully(
        gracePeriodMillis, timeoutMillis, TimeUnit.MILLISECONDS
    )

    // ── ステップ3: connection と worker の両方の完了を待機 ──
    val workersShutdownTime = measureTimeMillis {
        withStopException { shutdownConnections.sync() }
        withStopException { shutdownWorkers.sync() }
    }

    // ── ステップ4: callEventGroup を最後にシャットダウン ──
    // shareWorkGroup=true の場合は worker と call が同じグループなのでスキップ
    // PR #5230の改善点: 3.3.2では全グループ同時だったが、callは最後に回すようになった
    if (!configuration.shareWorkGroup) {
        withStopException {
            val timeoutMillis = (timeoutMillis - workersShutdownTime).coerceAtLeast(100L)
            callEventGroup.shutdownGracefully(noQuietPeriod, timeoutMillis, TimeUnit.MILLISECONDS).sync()
        }
    }
}
```

#### 3バージョンの比較

| 観点 | 3.0.3 | 3.3.2 | 3.4.0 (PR #5230) |
|---|---|---|---|
| チャネルclose | 非同期（finallyでsync） | 非同期（finallyでsync） | **同期（先にsync）** |
| connection quietPeriod | gracePeriodMillis | gracePeriodMillis | **0（即座に停止）** |
| worker quietPeriod | gracePeriodMillis | gracePeriodMillis | gracePeriodMillis |
| workerのシャットダウン開始タイミング | connection完了後 | connection開始直後（同時） | connection開始直後（同時） |
| callEventGroupの停止タイミング | worker/callが同時に開始 | worker/callが同時に開始 | **connection/worker完了後** |
| 時間管理 | なし | なし | **measureTimeMillisで残時間を計算** |

### その他の発見

#### stop()の二重呼び出し

SIGTERM受信時、`stop()` は以下の2つの経路から呼ばれる:
1. **JVMシャットダウンフックスレッド**（`ShutdownHookJvm.kt` 経由）
2. **メインスレッド**（`NettyApplicationEngine.start(wait=true)` 内の `closeFuture().sync()` が解除された後に `stop()` が呼ばれる）

ただし、消去テストにより二重呼び出しは根本原因ではないことを確認済み。

#### Nettyのバージョン差異

- Ktor 3.0.3: Netty 4.1.x
- Ktor 3.3.2: Netty 4.2.7

Netty 4.2の `shutdownGracefully()` のAPIセマンティクスに破壊的変更はなかった。

---

## 総合分析

### 原因

Ktor 3.3.1以降（3.3.2、3.3.3、3.4.0を含む）でグレースフルシャットダウンが効かない原因は、`NettyApplicationEngine.stop()` における**Nettyイベントグループのシャットダウン順序の変更**と、**Nettyの `shutdownGracefully()` の内部動作**の組み合わせである。

#### 変更の経緯

KTOR-8770（PR #5102、3.3.1）で「`shutdownGracePeriod` の2倍の時間ブロックする」問題を修正する際、`shutdownConnections.await()` を最後に移動した。これにより `workerEventGroup.shutdownGracefully()` が `connectionEventGroup` の完了を待たずに呼ばれるようになった。

#### Nettyの `shutdownGracefully()` の内部動作

##### クラス階層と委譲関係

Ktorの `workerEventGroup` からNettyの各チャネルクローズまでの委譲チェーン:

```
Ktor側:
  EventLoopGroupProxy（io.ktor.server.netty）
    └→ Kotlin の by delegate で全メソッドを委譲

Netty側（すべて io.netty）:
  NioEventLoopGroup                          ← netty-transport
    └→ extends MultithreadEventLoopGroup     ← netty-transport
        └→ extends MultithreadEventExecutorGroup  ← netty-common
             │
             │  children[] 配列で複数の子イベントループを保持
             │
             ├── children[0]: NioEventLoop   ← netty-transport
             ├── children[1]: NioEventLoop
             └── children[N]: NioEventLoop
                   └→ extends SingleThreadEventLoop      ← netty-transport
                       └→ extends SingleThreadEventExecutor  ← netty-common
```

`workerEventGroup` はグループであり、内部に複数の `NioEventLoop`（1スレッド＝1イベントループ）を子として持つ。クライアントからTCP接続が来ると、`workerEventGroup.next()` がラウンドロビンで子を1つ選び、そのチャネルを登録する。以降そのコネクションの全I/O操作はその1つの `NioEventLoop` スレッドが担当する。

##### `shutdownGracefully()` の委譲フロー

```
Ktor: workerEventGroup.shutdownGracefully(15000, 20000, MILLISECONDS)
  │
  │  EventLoopGroupProxy → by delegate でそのまま転送
  ▼
MultithreadEventExecutorGroup.shutdownGracefully(quietPeriod, timeout, unit)
  │
  │  // 全ての子イベントループに同じ引数で一斉通知
  │  for (child : children) {
  │      child.shutdownGracefully(quietPeriod, timeout, unit)
  │  }
  ▼
SingleThreadEventExecutor.shutdownGracefully(quietPeriod, timeout, unit)  ← 各子で実行
  │
  │  shutdown0() を呼ぶ:
  │    - CAS で volatile state フィールドを 4(STARTED) → 5(SHUTTING_DOWN) に変更
  │    - gracefulShutdownQuietPeriod, gracefulShutdownTimeout を保存
  │    - return（即座に戻る。ブロックしない）
  ▼
  isShuttingDown() == true（state >= 5）  ← 他スレッドから即座に見える
```

##### チャネルクローズのフロー

各 `NioEventLoop` は常時以下のループを実行している:

```
// SingleThreadIoEventLoop.run()
for (;;) {
    runIo()                          // セレクタでI/Oイベント処理
    if (isShuttingDown()) {          // state >= 5 かチェック ← ★ここで検知
        ioHandler.prepareToDestroy() // ★ 全チャネルを即座にクローズ
        runAllTasks()
        if (confirmShutdown())       // quietPeriod/timeout でスレッド終了判定
            break                    // ← quietPeriod はここで初めて評価される
    }
}
```

`prepareToDestroy()` の実装（`NioIoHandler`）:

```
// NioIoHandler.prepareToDestroy()
void prepareToDestroy() {
    selectAgain()                         // セレクタを同期
    for (key : selector.keys()) {         // 登録された全 SelectionKey を取得
        registrations.add(key の登録情報)   // DefaultNioRegistration を収集
    }
    for (reg : registrations) {
        reg.close()                       // ★ 各チャネルを無条件にクローズ
    }                                     //   → TCP RST/FIN がクライアントに送信される
}
```

##### 時系列まとめ

```
workerEventGroup.shutdownGracefully(quietPeriod=15000, timeout=20000)
  │  MultithreadEventExecutorGroup → 全子に一斉通知
  │  SingleThreadEventExecutor     → state を SHUTTING_DOWN に変更
  │  ← 即座に戻る（ブロックしない）
  ▼
各 NioEventLoop の次のループ反復（数ms以内）
  │  isShuttingDown() == true
  ▼
prepareToDestroy()
  │  NioIoHandler が selector.keys() の全チャネルをクローズ
  ▼
全クライアントコネクションが切断（TCP RST/FIN 送信）  ← curlが000を返す
  │
  │  ここから quietPeriod(15秒) のカウントが始まる
  │  （もう閉じるチャネルはないが、スレッドはまだ生きている）
  ▼
confirmShutdown() → true → スレッド終了
```

`quietPeriod` は `prepareToDestroy()` の**後**に `confirmShutdown()` で評価されるため、チャネルクローズを遅延させる効果はない。Netty側にもこの挙動を制御する設定は存在しない（[netty/netty#3699](https://github.com/netty/netty/issues/3699) で2015年に報告済み、未修正）。

#### 3.0.3で動作する理由

3.0.3では `connectionEventGroup` のシャットダウン完了を待ってから `workerEventGroup.shutdownGracefully()` を呼ぶ。`workerEventGroup` のイベントループにはクライアントコネクションのチャネルが登録されているが、`shutdownGracefully()` が呼ばれるまではイベントループは通常動作を続けるため、インフライトリクエスト（処理中のHTTPリクエスト）は正常に完了する。`connectionEventGroup` のgracePeriod（15秒）がそのまま猶予時間として機能する。

#### 3.3.1以降（3.3.2、3.3.3、3.4.0を含む）で動作しない理由

3.3.1以降では、すべてのバージョンで **`connectionEventGroup` の完了を待たずに `workerEventGroup.shutdownGracefully()` を呼んでいる**。これが根本原因であり、3.3.2でも3.4.0でも同じである。

`workerEventGroup.shutdownGracefully()` が呼ばれた瞬間:
- `isShuttingDown()` が即座に `true` になる
- 次のイベントループ反復で `closeAll()` が実行され、**クライアントコネクションを含むすべてのチャネルが即座にクローズされる**
- `quietPeriod=gracePeriodMillis` を設定していても、それはスレッドの終了を遅延させるだけで、チャネルのクローズには影響しない

結果として、SIGTERM後約15msでクライアントコネクションが切断される。プロセス自体は約20秒間生存する（イベントループスレッドがquietPeriod/timeoutまで待機するため）が、コネクションは既に失われている。

3.4.0のPR #5230は `callEventGroup` を最後にシャットダウンするよう改善したが、`workerEventGroup` の開始タイミングには手を付けていないため、同じ問題が残っている。

### 対策案

| # | 対策 | 概要 |
|---|---|---|
| 1 | **Ktor 3.0.3にダウングレード** | 3.0.3ではシャットダウン順序が正しく、グレースフルシャットダウンが機能する。ただし3.0.3以降のバグ修正・機能改善が失われる |
| 2 | **Ktorにissueを報告** | `workerEventGroup.shutdownGracefully()` の呼び出しを `connectionEventGroup` 完了後に移動する修正を提案。現在のKtor側はこの問題を認識していない可能性が高い |
| 3 | **カスタムNettyエンジンの実装** | `NettyApplicationEngine` を継承/コピーして `stop()` メソッドをオーバーライドし、3.0.3と同じ順序でシャットダウンするようにする |

※ カスタムシャットダウンフックによるワークアラウンド（`embeddedServer` + `Runtime.addShutdownHook`等）は、内部的に同じ `NettyApplicationEngine.stop()` を呼ぶため、根本原因を解決できない。

### 推奨

**短期的にはKtor 3.0.3へのダウングレード**、**中長期的にはKtorへのissue報告**を推奨する。

根本原因は `NettyApplicationEngine.stop()` 内部でNettyの `workerEventGroup.shutdownGracefully()` が早期に呼ばれることにある。Nettyの `shutdownGracefully()` はチャネルのクローズを即座に実行するため、`quietPeriod` パラメータではインフライトリクエストを保護できない。この問題はアプリケーション側のワークアラウンドでは対処できず、Ktor側での修正が必要である。

3.4.0のPR #5230は `callEventGroup` のシャットダウン順序を改善したが、`workerEventGroup` の即時シャットダウン（＝クライアントコネクションの即時切断）という根本的な問題には対処していない。Ktorの開発チームは `quietPeriod` がチャネルの即時クローズを防ぐと認識している可能性があり、issue報告により修正を促すことが望ましい。

### 未解決事項

調査中、System.out.printlnによるイベント追跡コード（ApplicationStarted/StopPreparing/Stopping/Stoppedの購読 + カスタムJVMフック）を**すべて同時に**追加した場合のみHTTP 200が返る現象が1度観測された（`logs/shutdown-332-sysout.log`）。個別に追加した場合はすべてHTTP 000だった。タイミングに依存する偶発的な成功の可能性が高いが、原因は特定できていない。
