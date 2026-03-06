# Netty + k8s preStop による グレースフルシャットダウン検証

## 背景

Ktor 3.3.1以降、Nettyエンジンのグレースフルシャットダウンが壊れている（[netty/VerificationResults.md](../netty/VerificationResults.md)）。
しかし、実際にissueとして報告がほとんど上がっていない。

仮説: k8s環境では `preStop` hook で `sleep` を入れることで、SIGTERMの前にインフライトリクエストが自然に捌き終わるため、アプリレベルのグレースフルシャットダウンが壊れていても誰も困っていない。

この仮説を実際にk8s上で検証する。

## 検証内容

Ktor 3.4.0 + Netty（グレースフルシャットダウンが壊れているバージョン）をk8sにデプロイし、以下の2パターンでrolling update中のリクエスト断を確認する。

### パターン1: preStop なし

- `preStop` hook を設定しない
- rolling update中に `/slow`（10秒かかる処理）へリクエストを送り続ける
- **期待結果: リクエストが中断される**（グレースフルシャットダウンが壊れているため）

### パターン2: preStop sleep あり

- `preStop` hook で `sleep 15` を設定する
- rolling update中に `/slow` へリクエストを送り続ける
- **期待結果: リクエストが正常完了する**（SIGTERMの前にServiceのendpointsから外れ、新規リクエストが来なくなり、既存リクエストが完了する猶予がある）

## 環境

- minikube（ローカルk8sクラスタ）
- `eval $(minikube docker-env)` でminikubeのDockerデーモンに直接ビルド（レジストリ不要）

## 構成

```
netty-with-k8s/
├── README.md
├── Dockerfile
├── pom.xml                      # netty/ から独立コピー
├── src/                         # netty/ から独立コピー
│   └── main/
│       ├── kotlin/com/example/Application.kt
│       └── resources/
│           ├── application.yaml
│           └── logback.xml
├── k8s/
│   ├── deployment.yaml          # preStopなし
│   ├── deployment-prestop.yaml  # preStop sleep 15
│   └── service.yaml             # NodePort Service
└── verify.sh                    # 全自動検証スクリプト
```

## 検証手順

`verify.sh` で以下を自動実行:

1. minikube start
2. minikube docker-env でイメージをビルド
3. kubectl apply（Service + Deployment）
4. Pod ready 待ち
5. パターン1（preStopなし）: `/slow` にリクエスト → rollout restart → HTTPステータス記録
6. パターン2（preStop sleep あり）: deployment差し替え → 同じテスト → HTTPステータス記録
7. 結果を表示
8. minikube stop && minikube delete