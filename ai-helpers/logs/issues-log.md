# 📋 ЖУРНАЛ ПРОБЛЕМ И РЕШЕНИЙ

> Накопленный опыт решения технических проблем в проекте PuntoPunto

---

## 🔍 001 - 2025-01-31 - Блокировка конверсии спецсимволов в ContextValidator - 🔧 Техническая

### 📊 **Контекст:**
- **Задача**: Убрать artificial gating для спецсимволов в validateBasicRequirements()
- **Окружение**: macOS Swift app, ContextValidator.swift
- **Предпосылки**: hasLetters() проверка блокировала любой текст без букв от конверсии

### ❌ **Проблема:**
- **Симптомы**: Спецсимволы типа "[];" блокировались с сообщением "Text contains no letters, skipping conversion"
- **Корневая причина**: Искусственное ограничение в validateBasicRequirements() метод через hasLetters() check
- **Влияние**: LayoutConverter не мог использовать свою полную функциональность для конверсии спецсимволов

### 🛠️ **Решение:**
- **Подход**: Полное удаление hasLetters() ограничения, делегирование ответственности LayoutConverter'у
- **Конкретные действия**: 
  ```swift
  // УДАЛЕНО:
  guard hasLetters(text) else {
      return (false, "Text contains no letters, skipping conversion")
  }
  // И удален сам метод hasLetters()
  ```
- **Результат**: Все non-empty content теперь проходит к LayoutConverter для оценки конвертируемости

### 📈 **Анализ:**
- **✅ Что сработало хорошо**: Принцип Single Responsibility - пусть LayoutConverter решает что конвертируемо
- **❌ Что не сработало**: Изначальное предположение что только текст с буквами нуждается в конверсии было неверным
- **💡 Уроки**: Artificial gating часто ограничивает функциональность больше чем защищает
- **🔄 Альтернативы**: Можно было расширить hasLetters() для спецсимволов, но удаление - более clean solution

### 🎯 **Применимость:**
- **Теги**: `#swift` `#validation` `#single-responsibility` `#minimalism` `#special-characters`
- **Похожие ситуации**: Любые validation layers которые дублируют логику downstream компонентов
- **Профилактика**: При создании validation логики, проверить не ограничивает ли она legitimate use cases

---

## 🔍 002 - 2025-01-31 - Односторонняя конверсия спецсимволов - 🏗️ Архитектурная

### 📊 **Контекст:**
- **Задача**: Исправить bidirectional конверсию спецсимволов (@, #, $ не конвертировались в RU эквиваленты)
- **Окружение**: LayoutConverter.swift, InputSourceManager.swift
- **Предпосылки**: После удаления hasLetters() блокировки обнаружена односторонняя конверсия

### ❌ **Проблема:**
- **Симптомы**: 
  - RU→EN работало: '"'→'@', '№'→'#', '%'→'$'
  - EN→RU НЕ работало: '@'→'@', '#'→'#', '$'→'$' (no change)
  - Логи показывали "Could not determine target layout for conversion"
- **Корневая причина**: 
  1. `detectPredominantLayout()` игнорировал спецсимволы (только `if char.isLetter`)
  2. `InputSourceManager.determineTargetLayout()` анализировал только буквы в CharacterSet
- **Влияние**: EN спецсимволы всегда детектировались как RU → нет конверсии, нет layout switching

### 🛠️ **Решение:**
- **Подход**: Расширить существующие detection methods для учета спецсимволов через mapping tables
- **Конкретные действия**:
  ```swift
  // LayoutConverter.detectPredominantLayout - добавлен else branch:
  } else {
      if enToRu[charString] != nil {
          enCount += 1
      } else if ruToEn[charString] != nil {
          ruCount += 1
      }
  }
  
  // InputSourceManager.determineTargetLayout - расширены CharacterSet:
  .union(CharacterSet(charactersIn: "\"№%:,.;()"))     // RU special chars
  .union(CharacterSet(charactersIn: "@#$%^&*()"))      // EN special chars
  ```
- **Результат**: Полная bidirectional конверсия @ ↔ ", # ↔ №, $ ↔ % с автоматическим layout switching

### 📈 **Анализ:**
- **✅ Что сработало хорошо**: 
  - Log analysis показал четкий паттерн проблемы
  - Systematic discovery через codebase_search нашел root causes быстро
  - Reuse existing mapping tables (enToRu/ruToEn) без создания новых структур
- **❌ Что не сработало**: Изначальная assumption что layout detection должен работать только с буквами
- **💡 Уроки**: 
  - Complete feature coverage важнее partial restrictions
  - Bidirectional testing essential для detection логики
  - Existing infrastructure часто можно reuse для новых requirements
- **🔄 Альтернативы**: Создание separate mapping tables для спецсимволов, но это было бы duplication

### 🎯 **Применимость:**
- **Теги**: `#swift` `#layout-detection` `#special-characters` `#bidirectional` `#character-sets` `#macos` `#minimalism`
- **Похожие ситуации**: Любые detection/classification системы которые должны работать с multiple character types
- **Профилактика**: При создании detection логики, убедиться что все relevant character types покрыты

---

*Записи добавляются только по запросу пользователя*
