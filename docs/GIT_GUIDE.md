# Git Guide

Git을 처음 사용하거나 익숙하지 않은 팀원을 위한 기본 사용 가이드입니다.

## Prerequisites

Windows 환경에서는 [Git for Windows](https://git-scm.com/downloads/win)를 설치하고 **Git Bash**를 사용합니다.

Git 명령어를 실행하기 전, 현재 작업 경로를 확인해 주세요.

| 명령어 | 설명 |
|---|---|
| `pwd` | 현재 작업 경로 확인 |
| `ls` | 파일 및 폴더 목록 확인 |
| `cd <path>` | 지정한 경로로 이동 |
| `cd ..` | 상위 디렉터리로 이동 |

## 1. Clone Repository

원격 저장소를 로컬 환경으로 복제합니다. `-b` 옵션을 사용하면 특정 브랜치를 선택하여 복제할 수 있습니다.

**Command**

```bash
git clone -b <branch-name> <repository-url>
cd <repository-name>
```

**Example**

```bash
git clone -b develop https://github.com/idec-resnet-project/resnet20-accelerator.git
cd /c/resnet20-accelerator
```

복제 후 현재 브랜치를 확인합니다.

```bash
git branch
```

> 현재 선택된 브랜치에는 `*`가 표시됩니다.

## 2. Configure Git User

커밋에 사용할 사용자 이름과 이메일을 설정합니다. `--global` 옵션을 사용하면 내 컴퓨터의 모든 프로젝트에 동일하게 적용됩니다.

```bash
git config --global user.name "<your-name>"
git config --global user.email "<your-email>"
```

설정된 사용자 정보를 확인합니다.

```bash
git config user.name
git config user.email
```

> 전체 설정은 `git config --list` 명령어로 확인할 수 있습니다.

설정을 완전히 지우고 싶다면 `--unset` 옵션을 사용합니다.

```bash
git config --global --unset user.name
git config --global --unset user.email
```

## 3. Create Personal Branch

`develop` 브랜치를 기준으로 개인 작업 브랜치를 생성합니다.

먼저 `develop` 브랜치로 이동하여 최신 코드를 가져옵니다.

```bash
git switch develop
git pull origin develop
```

**새로운 브랜치를 생성하는 경우**

`-c` 옵션을 사용하면 새로운 브랜치를 생성하고 해당 브랜치로 이동합니다.

```bash
git switch -c <type>/<team>-<name>
```

**Example**

```bash
git switch -c feat/core-idec
```

**이미 생성된 브랜치로 이동하는 경우**

```bash
git switch feat/core-idec
```

현재 브랜치를 확인합니다.

```bash
git branch
```

**Expected Output**

```text
  develop
* feat/core-idec
```

> 현재 선택된 브랜치에는 `*`가 표시됩니다. 브랜치 이름은 [Contributing Guide](../.github/CONTRIBUTING.md)의 규칙을 따릅니다.

## 4. Commit Changes

변경된 파일을 확인합니다.

```bash
git status
```

커밋할 파일을 선택하고 변경 사항을 기록합니다.

**Command**

```bash
git add <file-path>
git commit -m "<type>(<scope>): <description>"
```

**Example**

```bash
git add rtl/mac.v
git commit -m "feat(mac): implement MAC module"
```

- `git add`: 커밋에 포함할 파일을 선택합니다.
- `git commit -m`: 선택한 파일의 변경 사항을 메시지와 함께 기록합니다.

모든 변경 사항을 한 번에 추가하려면 다음 명령어를 사용합니다.

```bash
git add .
```

> `git add .`는 현재 디렉터리와 하위 디렉터리의 변경 사항을 추가합니다. 커밋하기 전 `git status`로 의도하지 않은 파일이 포함되지 않았는지 확인해 주세요.

## 5. Push Changes

로컬에서 커밋한 내용을 GitHub 원격 저장소에 업로드합니다.

**Command**

```bash
git push -u origin <branch-name>
```

**Example**

```bash
git push -u origin feat/core-idec
```

- `origin`: GitHub 원격 저장소의 이름입니다.
- `-u`: 이후 브랜치 이름을 입력하지 않고 `git push`만 사용할 수 있도록 설정하는 옵션입니다.

최초 Push 이후에는 다음 명령어만 사용하면 됩니다.

```bash
git push
```

> Push하기 전 `git branch`로 현재 작업 중인 브랜치를 확인해 주세요.

## 6. Update Personal Branch

다른 팀원이 `develop`에 반영한 최신 코드를 내 개인 브랜치에도 적용합니다.

**Command**

```bash
git switch develop
git pull origin develop
git switch <branch-name>
git merge develop
```

**Example**

```bash
git switch develop
git pull origin develop
git switch feat/core-idec
git merge develop
```

- `git switch develop`: `develop` 브랜치로 이동합니다.
- `git pull origin develop`: GitHub에 있는 최신 `develop` 코드를 가져옵니다.
- `git switch <branch-name>`: 내 개인 브랜치로 돌아옵니다.
- `git merge develop`: 최신 `develop`의 변경 사항을 내 브랜치에 합칩니다.

> 실행 전 작업 중인 변경 사항을 커밋하거나 임시 저장해 주세요. 코드가 충돌하면 충돌을 해결한 후 병합을 완료해야 합니다.

## 7. Create Pull Request

개인 브랜치에서 작업을 완료했다면, 변경한 코드를 `develop` 브랜치에 합치기 위해 **Pull Request(PR)**를 생성합니다.

### 1. GitHub에 코드 업로드

먼저 개인 브랜치의 변경 사항을 커밋하고 Push했는지 확인합니다.

```bash
git push
```

### 2. Pull Request 생성

1. GitHub 저장소에 접속합니다.
2. 상단의 **Pull requests** 탭을 클릭합니다.
3. **New pull request** 버튼을 클릭합니다.
4. 병합할 브랜치를 다음과 같이 선택합니다.

   - **Base: `develop`** — 변경 사항을 합칠 대상 브랜치
   - **Compare: `feat/core-idec`** — 내가 작업한 개인 브랜치

5. 변경된 파일과 코드를 확인합니다.
6. PR 제목과 작업 내용을 작성합니다.
7. **Create pull request** 버튼을 클릭합니다.

### 3. 코드 리뷰 및 병합

PR을 생성하면 다른 팀원이 변경 사항을 확인하고 리뷰할 수 있습니다.

리뷰 및 테스트가 완료되면 **Merge pull request**를 통해 `develop` 브랜치에 코드를 합칩니다.

> PR을 생성하는 것만으로 코드가 병합되지는 않습니다. 팀원들의 검토 후 병합을 진행합니다.