# 検証結果（CIOエンジン）

## 検証方法
- `/slow` エンドポイント（10秒かかる処理）にリクエスト送信中にSIGTERMを送信
- リクエストが正常に完了（HTTP 200）すればグレースフルシャットダウン成功
- Netty版と同一のKtorバージョン（3.4.0）、同一のapplication.yaml設定で検証

## Netty版との差分

エンジン以外の差分が出ないよう、以下のみ変更した:

| 項目 | Netty版 | CIO版 |
|---|---|---|
| Application.ktのimport | `io.ktor.server.netty.*` | `io.ktor.server.cio.*` |
| pom.xmlの依存 | `ktor-server-netty-jvm` | `ktor-server-cio-jvm` |
| pom.xmlのartifactId | `ktor-graceful-shutdown` | `ktor-graceful-shutdown-cio` |

application.yaml、logback.xml、検証スクリプトのロジック、Kotlin/Ktorバージョンはすべて同一。

## Ktor 3.4.0

| 設定 | 結果 |
|---|---|
| shutdownGracePeriod/Timeout設定あり | **リクエスト正常完了（グレースフルシャットダウン成功）** |

CIOエンジンでは `shutdownGracePeriod` / `shutdownTimeout` の設定によりグレースフルシャットダウンが正常に機能する。
Netty版で発生する「`workerEventGroup.shutdownGracefully()` によるクライアントコネクションの即時切断」はCIOエンジンには該当しない問題であり、CIOでは期待通りインフライトリクエストの完了を待ってからシャットダウンする。
