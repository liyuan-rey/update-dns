# Usage: PowerShell -File update-dns.ps1
# Description: Update DNS record on Cloudflare to point to the current public IP address.

param (
	[string]$LogFilePath = "update-dns.log"
)

$logPath = Join-Path -Path $PSScriptRoot -ChildPath $LogFilePath

function Write-CustomLog {
	param (
		[Parameter(Mandatory = $true)]
		[string]$LogFilePath,
		[Parameter(Mandatory = $true)]
		[string]$LogType,
		[Parameter(Mandatory = $true)]
		[string]$LogContent
	)
	# 获取当前时间
	$logTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	# 构建日志条目
	$logEntry = "$logTime - $LogType - $LogContent"
	try {
		# 将日志条目追加到日志文件中
		$logEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
	}
	catch {
		Write-Warning "写入日志文件时出错: $($_.Exception.Message)"
	}
}

function Write-InfoLog {
	param (
		[Parameter(Mandatory = $true)]
		[string]$LogContent
	)
	Write-CustomLog -LogFilePath $logPath -LogType "INFO" -LogContent $LogContent
}

function Write-WarningLog {
	param (
		[Parameter(Mandatory = $true)]
		[string]$LogContent
	)
	Write-CustomLog -LogFilePath $logPath -LogType "WARNING" -LogContent $LogContent
}

function IsValidIPv4 {
	param (
		[string]$ip
	)
	$pattern = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
	return $ip -match $pattern
}

try {
	# 从 .env 文件加载数据
	$envFilePath = Join-Path -Path $PSScriptRoot -ChildPath ".env"
	if (Test-Path -Path $envFilePath) {
		# 读取.env文件的所有行
		$envLines = Get-Content -Path $envFilePath

		# 遍历每一行
		foreach ($line in $envLines) {
			# 忽略空行和以#开头的注释行
			if ($line -notmatch "^\s*(#|$)") {
				# 使用等号分割键值对，并考虑等号两边可能存在的空格
				$keyValue = $line -split '\s*=\s*', 2

				if ($keyValue.Length -eq 2) {
					$key = $keyValue[0].Trim()
					$value = $keyValue[1].Trim()

					# 移除值中的引号
					if ($value -match "^([`"'])(.*)\1$") {
						$value = $matches[2]
					}

					# 将键值对设置为脚本变量
					Set-Variable -Name $key -Value $value -Scope Script

					# 输出设置的变量
					Write-InfoLog("Set Script variable: $key = $value")
				}
			}
		}
	}
	else {
		Write-WarningLog("The .env file was not found at $envFilePath.")
		exit 2
	}

	# 获取公网 IP
	$headers = @{
		"User-Agent" = "curl/8.10.1"
	}
    
	$ipResponse = Invoke-WebRequest -Uri "4.ipw.cn" -Headers $headers
	$publicIP = $ipResponse.Content
    
	# 检查 IP 格式
	if (-not (IsValidIPv4 -ip $publicIP)) {
		Write-WarningLog ("$publicIP 不是有效的 IPv4 地址。")
		exit 3
	}

	Write-InfoLog("公网 IPv4 地址 : $publicIP")

	# 检查 DNS 记录是否匹配最新 IP
	$subdomain = $ENV_SUBDOMAIN
	$domain = $ENV_DOMAIN
	$apiToken = $ENV_API_TOKEN
	# $email = $ENV_EMAIL
	# $apiKey = $ENV_API_KEY

	# 构建请求头
	$headers = @{
		"Content-Type"  = "application/json"
		"Authorization" = "Bearer $apiToken"
		# "X-Auth-Email" = $email
		# "X-Auth-Key" = "Bearer $apiKey"
	}

	
	# 获取 zone id
	$apiBaseUrl = "https://api.cloudflare.com/client/v4/zones"
	$zoneIdUrl = "$($apiBaseUrl)?name=$domain"
	$zoneIdResponse = Invoke-RestMethod -Uri $zoneIdUrl -Method Get -Headers $headers
	$zoneId = $zoneIdResponse.result[0].id

	# 获取 record id
	$recordIdUrl = "$apiBaseUrl/$zoneId/dns_records?type=A&name=$subdomain.$domain"
	$recordIdResponse = Invoke-RestMethod -Uri $recordIdUrl -Method Get -Headers $headers
	$recordId = $recordIdResponse.result[0].id

	try {
		# 解析域名对应的 IP 地址
		$dnsResults = Resolve-DnsName -Name $("$subdomain.$domain") -Type A -Server 1.1.1.1 -ErrorAction Stop

		# 遍历解析结果，检查是否有匹配的 IP 地址
		$isMatch = $false
		foreach ($result in $dnsResults) {
			Write-InfoLog("当前解析指向： $($result.IPAddress)")
			if ($result.IPAddress -eq $publicIP) {
				$isMatch = $true
				break
			}
		}

		if ($isMatch) {
			Write-InfoLog("域名 $subdomain.$domain 指向的 IP 地址与当前公网 IP 匹配，取消更新。")
			exit 0
		}
	}
	catch {
		Write-WarningLog("解析域名 $subdomain.$domain 时出现错误：$($_.Exception.Message)")
		exit 4
	}
	
	# 更新 Cloudflare DNS 记录
	$ipAddress = $publicIP
	$recordType = "A"
	$ttl = 1
	$proxied = $false

	# 构建 API 请求 URL
	$apiUrl = "$apiBaseUrl/$zoneId/dns_records"

	# 构建请求体
	$body = @{
		"comment" = "auto update dns at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
		"content" = $ipAddress
		"name"    = "$subdomain.$domain"
		"proxied" = $proxied
		"ttl"     = $ttl
		"type"    = $recordType
	} | ConvertTo-Json

	# 更新 DNS 记录
	try {
		# 检查是否已有记录
		$existingRecordUrl = "$apiUrl?type=$recordType&name=$subdomain.$domain"
		$existingResponse = Invoke-RestMethod -Uri $existingRecordUrl -Method Get -Headers $headers
		Write-InfoLog($existingResponse)
		if ($existingResponse.result -and $existingResponse.result.Count -gt 0) {
			# 有记录，进行更新
			$recordId = $existingResponse.result[0].id
			$updateUrl = "$apiUrl/$recordId"
			$response = Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $headers -Body $body
			if ($response.success) {
				Write-InfoLog("DNS 记录更新成功。")
			}
			else {
				Write-WarningLog("DNS 记录更新失败。错误信息: $($response.errors.message)")
				exit 5
			}
		}
		else {
			# 无记录，进行添加
			$response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
			if ($response.success) {
				Write-InfoLog("DNS 记录添加成功。")
			}
			else {
				Write-WarningLog("DNS 记录添加失败。错误信息: $($response.errors.message)")
				exit 6
			}
		}
	}
	catch {
		Write-WarningLog("检查或更新 DNS 记录出错: $($_.Exception.Message)")
		exit 7
	}
}
catch {
	Write-WarningLog("发生错误：$($_.Exception.Message)")
	exit 1
}

Write-InfoLog("------FINISH------")
