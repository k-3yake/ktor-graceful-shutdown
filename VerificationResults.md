# Ktor 3系 グレースフルシャットダウン検証結果

## 検証概要

Ktor 3系でのグレースフルシャットダウンの動作をエンジン別に検証する。
`/slow` エンドポイント（10秒かかる処理）にリクエスト送信中にSIGTERMを送信し、リクエストが正常完了（HTTP 200）するかを確認する。

## エンジン別検証結果

| エンジン | ディレクトリ | 状況 |
|---|---|---|
| **Netty** | [netty/](netty/) | 検証完了・原因特定済み |
| **CIO** | [cio/](cio/) | 検証完了 |

## Netty エンジン

詳細: [netty/VerificationResults.md](netty/VerificationResults.md)

### 結果サマリ

| バージョン | グレースフルシャットダウン |
|---|---|
| Ktor 3.0.3 | 成功 |
| Ktor 3.3.1以降（3.3.2, 3.3.3, 3.4.0） | **失敗** |

### 原因

KTOR-8770（PR #5102、3.3.1）で `NettyApplicationEngine.stop()` 内の `shutdownConnections.await()` の位置が変更され、`workerEventGroup.shutdownGracefully()` が `connectionEventGroup` の完了を待たずに呼ばれるようになった。Nettyの `shutdownGracefully()` は呼び出し直後に全チャネルを即座にクローズするため、`quietPeriod` パラメータではインフライトリクエストを保護できない。

アプリケーション側のワークアラウンドでは対処不可能であり、Ktor側の修正が必要。

## CIO エンジン

詳細: [cio/VerificationResults.md](cio/VerificationResults.md)

### 結果サマリ

| バージョン | グレースフルシャットダウン |
|---|---|
| Ktor 3.4.0 | **成功** |

CIOエンジンではNetty版と同一の `shutdownGracePeriod` / `shutdownTimeout` 設定でグレースフルシャットダウンが正常に機能する。Netty版の問題はNettyの `EventLoopGroup.shutdownGracefully()` の内部動作に起因するものであり、CIOには該当しない。

## エンジン間比較（Ktor 3.4.0）

| エンジン | グレースフルシャットダウン | 備考 |
|---|---|---|
| Netty | **失敗** | `workerEventGroup.shutdownGracefully()` が全コネクションを即座に切断 |
| CIO | **成功** | インフライトリクエストの完了を待ってからシャットダウン |
