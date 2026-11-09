# Contributing Guide

프로젝트의 일관된 협업과 변경 이력 관리를 위한 가이드입니다.

## Commit Convention

커밋 메시지는 [Conventional Commits](https://www.conventionalcommits.org/) 형식을 따릅니다.

### Format

```text
<type>(<scope>): <description>
```

- `type`: 변경 사항의 유형
- `scope`: 변경된 모듈 또는 영역 (선택)
- `description`: 변경 내용을 간결한 영어로 작성

### Types

| Type | Description |
|---|---|
| `feat` | 새로운 기능 또는 모듈 추가 |
| `fix` | 버그 수정 |
| `refactor` | 기능 변경 없는 코드 구조 개선 |
| `test` | 테스트 코드 추가 및 수정 |
| `docs` | 문서 추가 및 수정 |
| `style` | 공백, 들여쓰기 등 코드 포맷 변경 |
| `build` | 빌드 및 시뮬레이션 환경 변경 |
| `chore` | 기타 설정 및 유지보수 |

### Examples

```text
feat(core): implement MAC array
fix(memory): correct output logic
refactor(core): simplify datapath
test(memory): add testbench
docs: update README
chore: update .gitignore
```

## Pull Request Guidelines

- PR 제목은 커밋 메시지와 동일한 형식을 권장합니다.
- 변경 사항과 관련된 이슈가 있다면 연결합니다.
- PR 작성 시 [Pull Request Template](./PULL_REQUEST_TEMPLATE.md)을 사용합니다.

## Branch Convention

### Branch Naming

브랜치 이름은 다음 형식을 따릅니다.

```text
<type>/<team>-<name>
```

- `type`: 작업 유형 (`feat`, `fix`, `refactor` 등)
- `team`: 담당 팀 (`core`, `memory`, `embedded`)
- `name`: 팀원 이름

**Examples**

```text
feat/core-idec
```

### Branch Guidelines

- `main`: 최종 검증된 안정적인 코드를 관리합니다.
- `develop`: 각 팀원의 작업을 통합하고 테스트하는 브랜치입니다.
- `feat/<team>-<name>`: 각 팀원이 개별적으로 개발하는 작업 브랜치입니다.
- 모든 개발 작업은 개인 브랜치에서 진행하며, `main`과 `develop`에 직접 커밋하지 않습니다.
- 작업 완료 후 Pull Request를 통해 `develop`에 병합합니다.
- 통합 테스트 및 검증 완료 후 `develop`을 `main`에 병합합니다.
- 다른 팀원의 브랜치에 직접 변경 사항을 푸시하지 않습니다.