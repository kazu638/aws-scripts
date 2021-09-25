#! /bin/zsh

# ログファイルと標準出力・エラー出力先を指定
LOG_FILE=./$(basename ${0})_`date "+%Y%m%d_%H%M%S"`.log
DLETE_ROLE_FILE=delete_role_`date "+%Y%m%d_%H%M%S"`.log
DELETE_INSTANCE_PROFILE_FILE=delete_instance_profile_`date "+%Y%m%d_%H%M%S"`.log
# 4320000秒=50日
# 3456000秒=40日
# 2592000秒=30日
# DELETE_TIME以上使用していないIAMロールが削除対象
DELETE_TIME=2592000
DELETE_DAY=$(($DELETE_TIME / 86400))

exec > >(tee -a ${LOG_FILE}) 2>&1

# aws cliのプロファイル設定
if ([[ $1 == "--profile" ]] || [[ $1 == "-p" ]]) && [[ ! $2 == "" ]]; then
    profile=$2
elif [[ $1 == "" ]]; then
    profile="default"
else
    cat << EOM
Usage: $(basename "$0") [-p|--profile]
    -p, --profile PROFILE-NAME      Specify the profile to be used by aws cli
    None                            Use "default" as a profile for aws cli
EOM
    exit 1
fi

# 削除したくないIAMロールを指定. grepで除外する
except_role_list=("^AWSServiceRoleFor")

# 全てのロール（except_role_listを除く）を取得
role_list=($(aws iam list-roles --query "Roles[].[RoleName]" --output text --profile ${profile} | grep -vE \
    `i=1; \
    for except_role in $except_role_list
    do
        if [[ $i -eq $#except_role_list ]]; then
            echo -n $except_role
        else
            echo -n "${except_role}|"
        fi
        ((i++))
    done`))

if [[ ! $? -eq 0 ]]; then
    echo "IAMロール取得の際にエラーが発生しました"
    exit 1
fi

echo "取得したIAMロールのリスト" >> $LOG_FILE
for role in ${role_list[@]}
do
    echo $role >> $LOG_FILE
done

# 現にインスタンスで使用されているロールはロールリストから除外(削除しない)
associations_instance_profile_list=($(aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[].IamInstanceProfile.[Arn]" --output text --profile ${profile} | cut -d "/" -f2))

if [[ $#associations_instance_profile_list -ge 1 ]]; then
    target_role_list=()
    echo "現にインスタンスでインスタンスプロファイルのリスト（削除しない）" >> $LOG_FILE
    for instance_profile in $associations_instance_profile_list[@]
    do
        echo $instance_profile >> $LOG_FILE
        target_role=$(aws iam get-instance-profile --instance-profile-name $instance_profile --query "InstanceProfile.Roles[0].RoleName" --output text --profile ${profile})
        echo "インスタンスプロファイルにアタッチされたIAMロール ${target_role}" >> $LOG_FILE
        target_role_list+=$target_role
    done

    role_list=($(for role in $role_list[@]
    do
        echo $role
    done \
    | grep -vE \
    `i=1; \
    for target_role in $target_role_list
    do
        if [[ $i -eq $#target_role_list ]]; then
            echo -n $target_role
        else
            echo -n "${target_role}|"
        fi
        ((i++))
    done`))
fi

# IAMロール削除前にインスタンスプロファイルを削除する必要があるため、存在する全てのインスタンスプロファイルのリストを取得
# ただし現にインスタンスで使用されているインスタンスプロファイルは除外
if [[ $#associations_instance_profile_list -ge 1 ]]; then
    role_name_of_instance_profile_list=($(aws iam list-instance-profiles --profile $profile --query "InstanceProfiles[].Roles[].[RoleName]" --output text | grep -vE \
`f=1; \
for i in $associations_instance_profile_list[@]
do
    if [[ $f -eq $#associations_instance_profile_list ]]; then
        echo -n "${i}"
    else
        echo -n "${i}|"
    fi
    ((f++))
done`))
else
    role_name_of_instance_profile_list=($(aws iam list-instance-profiles --profile $profile --query "InstanceProfiles[].Roles[].[RoleName]" --output text))
fi

# ロールが削除基準に当たるかチェックし、削除基準に該当すればロールを削除リストに入れる
delete_role_list=()
echo "${DELETE_DAY}日以上使用していないIAMロールをチェックします"
for role in ${role_list[@]}
do
    echo "${role} のlast_used_dateを取得します" >> $LOG_FILE
    last_used_date=$(aws iam get-role --role-name $role --query "Role.RoleLastUsed.LastUsedDate" --output text --profile ${profile})
    echo $last_used_date >> $LOG_FILE

    if [[ $last_used_date == "None" ]]; then
        delete_role_list+=$role
        echo "追跡期間中のアクセスがないロール ${role} （削除対象）"
        continue
    fi

    last_used_date_epoc=$(date -jf "%Y-%m-%dT%H:%M:%S" "$(echo $last_used_date | sed s/+00:00$//)" "+%s")
    result_epoc=$(expr `date -u "+%s"` - $last_used_date_epoc)
    echo "現在日時 - 最終使用日時 = ${result_epoc}(秒)" >> $LOG_FILE

    if [[ $result_epoc -ge $DELETE_TIME ]] && ; then
        echo "${DELETE_DAY}日以上使用していないロール ${role} （削除対象）"
        delete_role_list+=$role
    fi
done

# 利用者に削除するロールの一覧を表示
echo "以下のロールを削除します"

for role in $delete_role_list[@]
do
    echo "・ ${role}"
done

# 削除の最終確認
echo -n "削除していいですか？[y/N]"
read answer

# Yyなら削除開始
case $answer in
    [Yy] )
    echo "削除を実行したロール" >> $DLETE_ROLE_FILE
    echo "削除を実行したインスタンスプロファイル" >> $DELETE_INSTANCE_PROFILE_FILE
    for role in $delete_role_list[@]
    do
        # インスタンフプロファイル削除
        for role_name_of_instance_profile in $role_name_of_instance_profile_list[@]
        do
            if [[ $role == $role_name_of_instance_profile ]]; then
                instance_profile_name=$(aws iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].[InstanceProfileName]" --profile $profile --output text)
                aws iam remove-role-from-instance-profile --instance-profile-name $instance_profile_name --role-name $role --profile $profile
                aws iam delete-instance-profile --instance-profile-name $instance_profile_name --profile $profile
                if [[ ! $? -eq 0 ]]; then
                    echo "インスタンスプロファイル ${instance_profile_name} 削除中にエラーが発生しました。"
                    exit 1
                fi
                echo "IAMロール ${role} のインスタンスプロファイル ${instance_profile_name} 削除完了"
                echo $instance_profile_name >> $DELETE_INSTANCE_PROFILE_FILE
            fi
        done
        # ロールのインラインポリシー削除
        inline_policy_list=($(aws iam list-role-policies --role-name $role --query "PolicyNames" --output text --profile $profile))
        if [[ -n $inline_policy_list ]]; then
            for policy_name in $inline_policy_list[@]
            do
                aws iam delete-role-policy --role-name $role --policy-name $policy_name --profile $profile
                if [[ ! $? -eq 0 ]]; then
                    echo "IAMロール ${role} インラインポリシー ${policy_name} を削除中にエラーが発生しました"
                    exit 1
                fi
            done
        fi
        # ロールの管理ポリシーデタッチ
        managed_policy_list=($(aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].[PolicyArn]" --output text --profile $profile))
        if [[ -n $managed_policy_list ]]; then
            for policy_arn in $managed_policy_list[@]
            do
                aws iam detach-role-policy --role-name $role --policy-arn $policy_arn --profile $profile
                if [[ ! $? -eq 0 ]]; then
                    echo "IAMロール ${role} から管理ポリシー ${policy_arn} をデタッチ中にエラーが発生しました"
                    exit 1
                fi
            done
        fi
        # ロール削除
        aws iam delete-role --role-name $role --profile $profile
        if [[ ! $? -eq 0 ]]; then
            echo "IAMロール ${role} 削除中にエラーが発生しました"
            exit 1
        fi
        echo "IAMロール ${role} 削除完了"
        echo $role >> $DLETE_ROLE_FILE
    done
    ;;
    *)
    echo "スクリプト終了"
    exit 0
    ;;
esac