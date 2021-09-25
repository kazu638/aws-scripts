# old_iam_role_delete_script.sh

## 概要

スクリプト内の変数`DELETE_TIME`で指定された秒数間使用されていない IAM ロールを削除する。
変数`except_role_list`に削除不可の IAM ロールを記載する。
引数で aws cli の profile を指定可能。

## 引数

```
Usage: ./old_iam_role_delete_script.sh [-p|--profile]
    -p, --profile PROFILE-NAME      Specify the profile to be used by aws cli
    None                            Use "default" as a profile for aws cli
```

## ログ
スクリプト実行時、標準出力以外にログファイルが出力される。以下ログファイルの例。
- スクリプトのログ
    - `old_iam_role_delete_script.sh_20210925_195844.log`
- 削除したインスタンスプロファイルリスト
    - `delete_instance_profile_20210925_195844.log`
- 削除したIAMロールリスト
    - `delete_role_20210925_195844.log`


## 実行例

10 日使用していない IAM ロールを削除対象に指定し、削除不可の IAM ロールを指定した場合の実行結果。

```
except_role_list=("^AWSServiceRoleFor" "hoge-role" "fuga-role")
```

```
[21-09-25 19:58 ~/aws]# ./old_iam_role_delete_script.sh --profile {profile-name}
10日以上使用していないIAMロールをチェックします
10日以上使用していないロール LambdaExecutionS3AccessRole （削除対象）
10日以上使用していないロール new-resource-all-delete-role-nuiqf714 （削除対象）
10日以上使用していないロール new-resource-delete-role-038dhko1 （削除対象）
追跡期間中のアクセスがないロール test （削除対象）
以下のロールを削除します
・ DeliverLogsRole-CreateVpcFlowLogs
・ LambdaExecutionS3AccessRole
・ new-resource-all-delete-role-nuiqf714
・ new-resource-delete-role-038dhko1
・ test
削除していいですか？[y/N]y
IAMロール LambdaExecutionS3AccessRole 削除完了
IAMロール new-resource-all-delete-role-nuiqf714 削除完了
IAMロール new-resource-delete-role-038dhko1 削除完了
IAMロール test のインスタンスプロファイル test 削除完了
IAMロール test 削除完了
```
