-- Profile menu and translations adapted from AceDBOptions-3.0.
--[[
Copyright (c) 2007, Ace3 Development Team

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Redistribution of a stand alone version is strictly prohibited without
      prior written authorization from the Lead of the Ace3 Development Team.
    * Neither the name of the Ace3 Development Team nor the names of its contributors
      may be used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local _, Data = ...

local BattleGroundEnemies = BattleGroundEnemies
local addonLocale = Data.L
local UnitClass = UnitClass
local strlenutf8 = _G.strlenutf8

-- stylua: ignore start
local L = {
	choose = "Existing Profiles",
	choose_desc = "You can either create a new profile by entering a name in the editbox, or choose one of the already existing profiles.",
	choose_sub = "Select one of your currently available profiles.",
	copy = "Copy From",
	copy_desc = "Copy the settings from one existing profile into the currently active profile.",
	current = "Current Profile:",
	default = "Default",
	delete = "Delete a Profile",
	delete_confirm = "Are you sure you want to delete the selected profile?",
	delete_desc = "Delete existing and unused profiles from the database to save space, and cleanup the SavedVariables file.",
	delete_sub = "Deletes a profile from the database.",
	intro = "You can change the active database profile, so you can have different settings for every character.",
	name_too_long = "Profile names cannot be longer than 50 characters.",
	new = "New",
	new_sub = "Create a new empty profile.",
	profiles = "Profiles",
	profiles_sub = "Manage Profiles",
	reset = "Reset Profile",
	reset_desc = "Reset the current profile back to its default values, in case your configuration is broken, or you simply want to start over.",
	reset_sub = "Reset the current profile to the default",
	transfer_desc = "Import a profile or export your current one.",
}

local LOCALE = GetLocale()
if LOCALE == "deDE" then
	L["choose"] = "Vorhandene Profile"
	L["choose_desc"] = "Du kannst ein neues Profil erstellen, indem du einen neuen Namen in der Eingabebox 'Neu' eingibst, oder wähle eines der vorhandenen Profile aus."
	L["choose_sub"] = "Wählt ein bereits vorhandenes Profil aus."
	L["copy"] = "Kopieren von..."
	L["copy_desc"] = "Kopiere die Einstellungen von einem vorhandenen Profil in das aktive Profil."
	L["current"] = "Aktuelles Profil:"
	L["default"] = "Standard"
	L["delete"] = "Profil löschen"
	L["delete_confirm"] = "Willst du das ausgewählte Profil wirklich löschen?"
	L["delete_desc"] = "Lösche vorhandene oder unbenutzte Profile aus der Datenbank, um Platz zu sparen und die SavedVariables-Datei 'sauber' zu halten."
	L["delete_sub"] = "Löscht ein Profil aus der Datenbank."
	L["intro"] = "Hier kannst du das aktive Datenbankprofil ändern, damit du verschiedene Einstellungen für jeden Charakter erstellen kannst, wodurch eine sehr flexible Konfiguration möglich wird."
	L["name_too_long"] = "Profilnamen können nicht länger als 50 Zeichen sein."
	L["new"] = "Neu"
	L["new_sub"] = "Ein neues Profil erstellen."
	L["profiles"] = "Profile"
	L["profiles_sub"] = "Profile verwalten"
	L["reset"] = "Profil zurücksetzen"
	L["reset_desc"] = "Setzt das momentane Profil auf Standardwerte zurück, für den Fall, dass mit der Konfiguration etwas schief lief oder weil du einfach neu starten willst."
	L["reset_sub"] = "Das aktuelle Profil auf Standard zurücksetzen."
	L["transfer_desc"] = "Importiere ein Profil oder exportiere das aktuelle."
elseif LOCALE == "frFR" then
	L["choose"] = "Profils existants"
	L["choose_desc"] = "Vous pouvez créer un nouveau profil en entrant un nouveau nom dans la boîte de saisie, ou en choississant un des profils déjà existants."
	L["choose_sub"] = "Permet de choisir un des profils déjà disponibles."
	L["copy"] = "Copier à partir de"
	L["copy_desc"] = "Copie les paramètres d'un profil déjà existant dans le profil actuellement actif."
	L["current"] = "Profil actuel :"
	L["default"] = "Défaut"
	L["delete"] = "Supprimer un profil"
	L["delete_confirm"] = "Etes-vous sûr de vouloir supprimer le profil sélectionné ?"
	L["delete_desc"] = "Supprime les profils existants inutilisés de la base de données afin de gagner de la place et de nettoyer le fichier SavedVariables."
	L["delete_sub"] = "Supprime un profil de la base de données."
	L["intro"] = "Vous pouvez changer le profil actuel afin d'avoir des paramètres différents pour chaque personnage, permettant ainsi d'avoir une configuration très flexible."
	L["name_too_long"] = "Les noms de profil ne peuvent pas dépasser 50 caractères."
	L["new"] = "Nouveau"
	L["new_sub"] = "Créée un nouveau profil vierge."
	L["profiles"] = "Profils"
	L["profiles_sub"] = "Gestion des profils"
	L["reset"] = "Réinitialiser le profil"
	L["reset_desc"] = "Réinitialise le profil actuel au cas où votre configuration est corrompue ou si vous voulez tout simplement faire table rase."
	L["reset_sub"] = "Réinitialise le profil actuel avec les paramètres par défaut."
	L["transfer_desc"] = "Importez un profil ou exportez le profil actuel."
elseif LOCALE == "koKR" then
	L["choose"] = "기존 프로필"
	L["choose_desc"] = "편집 상자에 이름을 입력하여 새로운 프로필을 만들거나 이미 존재하는 프로필 중 하나를 선택할 수 있습니다."
	L["choose_sub"] = "현재 이용할 수 있는 프로필 중 하나를 선택합니다."
	L["copy"] = "복사해 올 프로필"
	L["copy_desc"] = "기존 프로필의 설정을 현재 활성화된 프로필로 복사합니다."
	L["current"] = "현재 프로필:"
	L["default"] = "기본값"
	L["delete"] = "프로필 삭제"
	L["delete_confirm"] = "선택한 프로필을 삭제하시겠습니까?"
	L["delete_desc"] = "데이터베이스에서 기존 프로필과 사용하지 않는 프로필을 삭제하여 공간을 절약하고 SavedVariables 파일을 정리합니다."
	L["delete_sub"] = "데이터베이스에서 프로필을 삭제합니다."
	L["intro"] = "활성 데이터베이스 프로필을 변경할 수 있으며, 모든 캐릭터마다 서로 다른 설정을 지정할 수 있습니다."
	L["name_too_long"] = "프로필 이름은 50자리를 초과할 수 없습니다."
	L["new"] = "새로운 프로필"
	L["new_sub"] = "비어 있는 프로필을 새로 만듭니다."
	L["profiles"] = "프로필"
	L["profiles_sub"] = "프로필 관리"
	L["reset"] = "프로필 재설정"
	L["reset_desc"] = "구성이 손상되었거나 처음부터 다시 시작하고 싶은 경우 현재 프로필을 기본값으로 재설정하세요."
	L["reset_sub"] = "현재 프로필을 기본값으로 재설정합니다"
	L["transfer_desc"] = "프로필을 가져오거나 현재 프로필을 내보냅니다."
elseif LOCALE == "esES" or LOCALE == "esMX" then
	L["choose"] = "Perfiles existentes"
	L["choose_desc"] = "Puedes crear un nuevo perfil introduciendo un nombre en el recuadro o puedes seleccionar un perfil de los ya existentes."
	L["choose_sub"] = "Selecciona uno de los perfiles disponibles."
	L["copy"] = "Copiar de"
	L["copy_desc"] = "Copia los ajustes de un perfil existente al perfil actual."
	L["current"] = "Perfil actual:"
	L["default"] = "Por defecto"
	L["delete"] = "Borrar un Perfil"
	L["delete_confirm"] = "¿Estas seguro que quieres borrar el perfil seleccionado?"
	L["delete_desc"] = "Borra los perfiles existentes y sin uso de la base de datos para ganar espacio y limpiar el archivo SavedVariables."
	L["delete_sub"] = "Borra un perfil de la base de datos."
	L["intro"] = "Puedes cambiar el perfil activo de tal manera que cada personaje tenga diferentes configuraciones."
	L["name_too_long"] = "Los nombres de perfil no pueden exceder los 50 caracteres."
	L["new"] = "Nuevo"
	L["new_sub"] = "Crear un nuevo perfil vacio."
	L["profiles"] = "Perfiles"
	L["profiles_sub"] = "Manejar Perfiles"
	L["reset"] = "Reiniciar Perfil"
	L["reset_desc"] = "Reinicia el perfil actual a los valores por defectos, en caso de que se haya estropeado la configuración o quieras volver a empezar de nuevo."
	L["reset_sub"] = "Reinicar el perfil actual al de por defecto"
	L["transfer_desc"] = "Importa un perfil o exporta el actual."
elseif LOCALE == "zhTW" then
	L["choose"] = "現有的設定檔"
	L["choose_desc"] = "您可以在文字方塊內輸入名字以建立新的設定檔，或是選擇一個現有的設定檔使用。"
	L["choose_sub"] = "從當前可用的設定檔裡面選擇一個。"
	L["copy"] = "複製自"
	L["copy_desc"] = "從一個現有的設定檔，將設定複製到現在使用中的設定檔。"
	L["current"] = "目前設定檔："
	L["default"] = "預設"
	L["delete"] = "刪除一個設定檔"
	L["delete_confirm"] = "確定要刪除所選擇的設定檔嗎？"
	L["delete_desc"] = "從資料庫裡刪除不再使用的設定檔，以節省空間，並且清理 SavedVariables 檔案。"
	L["delete_sub"] = "從資料庫裡刪除一個設定檔。"
	L["intro"] = "您可以從資料庫中選擇一個設定檔來使用，如此就可以讓每個角色使用不同的設定。"
	L["name_too_long"] = "設定檔名稱不能超過50個字元。"
	L["new"] = "新建"
	L["new_sub"] = "新建一個空的設定檔。"
	L["profiles"] = "設定檔"
	L["profiles_sub"] = "管理設定檔"
	L["reset"] = "重置設定檔"
	L["reset_desc"] = "將現用的設定檔重置為預設值；用於設定檔損壞，或者單純想要重來的情況。"
	L["reset_sub"] = "將目前的設定檔重置為預設值"
	L["transfer_desc"] = "匯入設定檔或匯出目前的設定檔。"
elseif LOCALE == "zhCN" then
	L["choose"] = "现有的配置文件"
	L["choose_desc"] = "你可以通过在文本框内输入一个名字创立一个新的配置文件，也可以选择一个已经存在的配置文件。"
	L["choose_sub"] = "从当前可用的配置文件里面选择一个。"
	L["copy"] = "复制自"
	L["copy_desc"] = "从当前某个已保存的配置文件复制到当前正使用的配置文件。"
	L["current"] = "当前配置文件："
	L["default"] = "默认"
	L["delete"] = "删除一个配置文件"
	L["delete_confirm"] = "你确定要删除所选择的配置文件么？"
	L["delete_desc"] = "从数据库里删除不再使用的配置文件，以节省空间，并且清理SavedVariables文件。"
	L["delete_sub"] = "从数据库里删除一个配置文件。"
	L["intro"] = "你可以选择一个活动的数据配置文件，这样你的每个角色就可以拥有不同的设置值，可以给你的插件配置带来极大的灵活性。"
	L["name_too_long"] = "配置文件名称不能超过50个字符。"
	L["new"] = "新建"
	L["new_sub"] = "新建一个空的配置文件。"
	L["profiles"] = "配置文件"
	L["profiles_sub"] = "管理配置文件"
	L["reset"] = "重置配置文件"
	L["reset_desc"] = "将当前的配置文件恢复到它的默认值，用于你的配置文件损坏，或者你只是想重来的情况。"
	L["reset_sub"] = "将当前的配置文件恢复为默认值"
	L["transfer_desc"] = "导入配置文件或导出当前配置文件。"
elseif LOCALE == "ruRU" then
	L["choose"] = "Существующие профили"
	L["choose_desc"] = "Вы можете создать новый профиль, введя название в поле ввода, или выбрать один из уже существующих профилей."
	L["choose_sub"] = "Выбор одного из уже доступных профилей."
	L["copy"] = "Скопировать из"
	L["copy_desc"] = "Копирование настроек из выбранного профиля в активный."
	L["current"] = "Текущий профиль:"
	L["default"] = "По умолчанию"
	L["delete"] = "Удалить профиль"
	L["delete_confirm"] = "Вы уверены, что хотите удалить выбранный профиль?"
	L["delete_desc"] = "Удаление существующего и неиспользуемого профиля из базы данных для сохранения места, и очистка файла SavedVariables."
	L["delete_sub"] = "Удаление профиля из базы данных."
	L["intro"] = "Изменяя активный профиль, Вы можете задать разные настройки для каждого персонажа."
	L["name_too_long"] = "Имена профилей не могут превышать 50 символов."
	L["new"] = "Новый"
	L["new_sub"] = "Создание нового чистого профиля."
	L["profiles"] = "Профили"
	L["profiles_sub"] = "Управление профилями"
	L["reset"] = "Сбросить профиль"
	L["reset_desc"] = "Сброс текущего профиля к стандартным настройкам, если Ваша конфигурация испорчена или Вы хотите настроить все заново."
	L["reset_sub"] = "Сброс текущего профиля на стандартный"
	L["transfer_desc"] = "Импортируйте профиль или экспортируйте текущий."
elseif LOCALE == "itIT" then
	L["choose"] = "Profili Esistenti"
	L["choose_desc"] = "Puoi creare un nuovo profilo digitando il nome della casella di testo, oppure scegliendone uno tra i profili già esistenti."
	L["choose_sub"] = "Seleziona uno dei profili attualmente disponibili."
	L["copy"] = "Copia Da"
	L["copy_desc"] = "Copia le impostazioni da un profilo esistente nel profilo attivo in questo momento."
	L["current"] = "Profilo Attivo:"
	L["default"] = "Predefinito"
	L["delete"] = "Cancella un Profilo"
	L["delete_confirm"] = "Sei sicuro di voler cancellare il profilo selezionato?"
	L["delete_desc"] = "Cancella i profili non utilizzati dal database per risparmiare spazio e mantenere puliti i file di configurazione SavedVariables."
	L["delete_sub"] = "Cancella un profilo dal Database."
	L["intro"] = "Puoi cambiare il profilo attivo, in modo da usare impostazioni diverse per ogni personaggio."
	L["name_too_long"] = "Il nome del profilo non può superare i 50 caratteri."
	L["new"] = "Nuovo"
	L["new_sub"] = "Crea un nuovo profilo vuoto."
	L["profiles"] = "Profili"
	L["profiles_sub"] = "Gestisci Profili"
	L["reset"] = "Reimposta Profilo"
	L["reset_desc"] = "Riporta il tuo profilo attivo alle sue impostazioni predefinite, nel caso in cui la tua configurazione si sia corrotta, o semplicemente tu voglia re-inizializzarla."
	L["reset_sub"] = "Reimposta il profilo ai suoi valori predefiniti."
	L["transfer_desc"] = "Importa un profilo o esporta quello attuale."
elseif LOCALE == "ptBR" then
	L["choose"] = "Perfis Existentes"
	L["choose_desc"] = "Você pode tanto criar um perfil novo tanto digitando um nome na caixa de texto, quanto escolher um dos perfis já existentes."
	L["choose_sub"] = "Selecione um de seus perfis atualmente disponíveis."
	L["copy"] = "Copiar De"
	L["copy_desc"] = "Copia as definições de um perfil existente no perfil atualmente ativo."
	L["current"] = "Perfil Autal:"
	L["default"] = "Padrão"
	L["delete"] = "Remover um Perfil"
	L["delete_confirm"] = "Tem certeza que deseja remover o perfil selecionado?"
	L["delete_desc"] = "Remove perfis existentes e inutilizados do banco de dados para economizar espaço, e limpar o arquivo SavedVariables."
	L["delete_sub"] = "Remove um perfil do banco de dados."
	L["intro"] = "Você pode alterar o perfil do banco de dados ativo, para que possa ter definições diferentes para cada personagem."
	L["name_too_long"] = "O nome do perfil não pode exceder 50 caracteres."
	L["new"] = "Novo"
	L["new_sub"] = "Cria um novo perfil vazio."
	L["profiles"] = "Perfis"
	L["profiles_sub"] = "Gerenciar Perfis"
	L["reset"] = "Resetar Perfil"
	L["reset_desc"] = "Reseta o perfil atual para os valores padrões, no caso de sua configuração estar quebrada, ou simplesmente se deseja começar novamente."
	L["reset_sub"] = "Resetar o perfil atual ao padrão"
	L["transfer_desc"] = "Importe um perfil ou exporte o atual."
end

-- stylua: ignore end

local function getProfileList(db, commonProfiles, excludeCurrent)
  local profiles = {}
  local currentProfile = db:GetCurrentProfile()
  for _, name in ipairs(db:GetProfiles()) do
    if not excludeCurrent or name ~= currentProfile then
      profiles[name] = name
    end
  end

  for name, label in pairs(commonProfiles) do
    if not excludeCurrent or profiles[name] then
      profiles[name] = label
    end
  end

  return profiles
end

local ProfileOptions = {}

function ProfileOptions:Reset()
  self.db:ResetProfile()
end

function ProfileOptions:SetProfile(_, value)
  self.db:SetProfile(value)
end

function ProfileOptions:GetCurrentProfile()
  return self.db:GetCurrentProfile()
end

function ProfileOptions:ListProfiles(info)
  return getProfileList(self.db, self.commonProfiles, info.arg == "nocurrent")
end

function ProfileOptions:HasNoProfiles(info)
  return next(self:ListProfiles(info)) == nil
end

function ProfileOptions:CopyProfile(_, value)
  self.db:CopyProfile(value)
end

function ProfileOptions:DeleteProfile(_, value)
  self.db:DeleteProfile(value)
end

local options = {
  desc = {
    order = 1,
    type = "description",
    name = L["intro"] .. "\n",
  },
  descreset = {
    order = 9,
    type = "description",
    name = L["reset_desc"],
  },
  reset = {
    order = 10,
    type = "execute",
    name = L["reset"],
    desc = L["reset_sub"],
    func = "Reset",
  },
  current = {
    order = 11,
    type = "description",
    name = function(info)
      return L["current"] .. " " .. NORMAL_FONT_COLOR_CODE .. info.handler:GetCurrentProfile() .. FONT_COLOR_CODE_CLOSE
    end,
    width = "default",
  },
  choosedesc = {
    order = 20,
    type = "description",
    name = "\n" .. L["choose_desc"],
  },
  new = {
    name = L["new"],
    desc = L["new_sub"],
    type = "input",
    order = 30,
    get = false,
    set = "SetProfile",
    usage = L["name_too_long"],
    validate = function(_, text)
      local length = strlenutf8(text)
      if length > 50 or length == 0 or text:find("^ +$") then
        return false
      end
      return true
    end,
    width = 2,
  },
  choose = {
    name = L["choose"],
    desc = L["choose_sub"],
    type = "select",
    order = 40,
    get = "GetCurrentProfile",
    set = "SetProfile",
    values = "ListProfiles",
    arg = "common",
    width = 2,
  },
  copydesc = {
    order = 50,
    type = "description",
    name = "\n" .. L["copy_desc"],
  },
  copyfrom = {
    order = 60,
    type = "select",
    name = L["copy"],
    desc = L["copy_desc"],
    get = false,
    set = "CopyProfile",
    values = "ListProfiles",
    disabled = "HasNoProfiles",
    arg = "nocurrent",
    width = 2,
  },
  deldesc = {
    order = 70,
    type = "description",
    name = "\n" .. L["delete_desc"],
  },
  delete = {
    order = 80,
    type = "select",
    name = L["delete"],
    desc = L["delete_sub"],
    get = false,
    set = "DeleteProfile",
    values = "ListProfiles",
    disabled = "HasNoProfiles",
    arg = "nocurrent",
    confirm = true,
    confirmText = L["delete_confirm"],
    width = 2,
  },
  transferdesc = {
    order = 85,
    type = "description",
    name = "\n" .. L["transfer_desc"],
  },
  transfer = {
    type = "group",
    name = "",
    inline = true,
    order = 90,
    args = {
      ImportButton = {
        type = "execute",
        name = addonLocale.ImportButton,
        desc = addonLocale.ImportButton_Desc,
        func = function()
          BattleGroundEnemies:ImportExportFrameSetupForMode("Import")
        end,
        order = 1,
      },
      ExportButton = {
        type = "execute",
        name = addonLocale.ExportButton,
        desc = addonLocale.ExportButton_Desc,
        func = function()
          return BattleGroundEnemies:ExportButtonPressed()
        end,
        order = 2,
      },
    },
  },
}

function Data.CreateProfileOptions(db)
  local commonProfiles = {
    Default = L["default"],
    [db.keys.char] = db.keys.char,
    [db.keys.realm] = db.keys.realm,
    [db.keys.class] = UnitClass("player"),
  }
  return {
    type = "group",
    name = L["profiles"],
    desc = L["profiles_sub"],
    handler = setmetatable({ db = db, commonProfiles = commonProfiles }, { __index = ProfileOptions }),
    args = options,
  }
end
