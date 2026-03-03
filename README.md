# ktor-graceful-shutdown
Ktorのグレースフルシャットダウンを試す

## 使用技術
- ktor 
  - versonは3系
  - EngineMain
  - netty
- maven

## その他
- 検証はshを作成して実施する
- グレースフルシャットダウンを検証するのに必要最低限の実装を行う

## TODO
- 1.検証対象のapiを作成
- 2.検証のshを作成し、グレースフルシャットダウン出来てないことを確認
- 3.グレースフルシャットダウン出来るようにする
- 4.再度検証

## 検証結果

### 検証方法
- `/slow` エンドポイント（10秒かかる処理）にリクエスト送信中にSIGTERMを送信
- リクエストが正常に完了（HTTP 200）すればグレースフルシャットダウン成功

### Ktor 3.0.3
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

### Ktor 3.3.2
同じ `shutdownGracePeriod` / `shutdownTimeout` の設定では**グレースフルシャットダウンが効かなかった**。

| 設定 | 結果 |
|---|---|
| shutdownGracePeriod/Timeout設定あり | リクエスト中断（グレースフルシャットダウン不可） |