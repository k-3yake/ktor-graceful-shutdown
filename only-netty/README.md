ma# Netty単独グレースフルシャットダウン検証

## 目的

Ktor を介さず、純粋な Netty のみでグレースフルシャットダウンが機能するかを検証する。

## 検証条件

- **Netty 4.2.7.Final**（Ktor 3.3.3 が使用するバージョンと同一）
- Kotlin 2.2.0 / Maven
- `/slow`（10秒かかる処理）と `/health` の2エンドポイント
- `shutdownGracefully(15秒, 20秒)`

## 実装方針

### HTTPサーバー

Netty 組み込みの HTTP コーデックのみで実装。フレームワークは使用しない。

- `ServerBootstrap` + `NioEventLoopGroup`（bossGroup / workerGroup の2グループ構成）
- `HttpServerCodec` + `HttpObjectAggregator` + カスタム `SimpleChannelInboundHandler`
- `/health`: 即座に 200 を返す
- `/slow`: `Thread.sleep(10000)` で10秒待機後に 200 を返す
  - Netty 単独のためコルーチンは使わない（Ktor版の `delay(10000)` との差異）
- サーバーの起動・停止をテストから制御できるようクラスとして切り出す

### シャットダウン

Netty 公式ガイドの推奨パターンに従う:

```kotlin
// サーバー停止時
serverChannel.close().sync()
workerGroup.shutdownGracefully(15, 20, TimeUnit.SECONDS)
bossGroup.shutdownGracefully(15, 20, TimeUnit.SECONDS)
```

### 検証方法

JUnit テストで検証する。デバッガでの追跡を容易にするため。

```kotlin
@Test
fun `inflight request completes during graceful shutdown`() {
    // 1. サーバー起動（localhost:0 でランダムポート）
    // 2. /slow にリクエスト送信（別スレッド）
    // 3. 2秒待機
    // 4. シャットダウン処理を呼ぶ
    // 5. レスポンスが 200 であることを assert
}
```
