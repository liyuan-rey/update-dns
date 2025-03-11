
function IsValidIPv4 {
    param (
        [string]$ip
    )
    $pattern = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    return $ip -match $pattern
}

try {
	# 获取公网 IP
    $headers = @{
        "User-Agent" = "curl/8.10.1"
    }
    
    $ipResponse = Invoke-WebRequest -Uri "4.ipw.cn" -Headers $headers
	$publicIP = $ipResponse.Content
    
	# 检查 IP 格式
	if (-not (IsValidIPv4 -ip $publicIP)) {
		Write-Host "$publicIP 不是有效的 IPv4 地址。"
		exit 1
	}

    Write-Host "公网 IPv4 地址 : $publicIP"

	# 检查 DNS 记录是否匹配最新 IP
	$subdomain = "test"
	$domain = "example.com"

	try {
		# 解析域名对应的 IP 地址
		$dnsResults = Resolve-DnsName -Name $("$subdomain.$domain") -Type A -ErrorAction Stop

		# 遍历解析结果，检查是否有匹配的 IP 地址
		$isMatch = $false
		foreach ($result in $dnsResults) {
			if ($result.IPAddress -eq $publicIP) {
				$isMatch = $true
				break
			}
		}

		if ($isMatch) {
			Write-Host "域名 $subdomain.$domain 指向的 IP 地址与当前公网 IP 匹配。"
			Write-Host "取消更新。"
			exit 0
		}
	}
	catch {
		Write-Host "解析域名 $subdomain.$domain 时出现错误：$($_.Exception.Message)"
	}
	
    # 记录最新 IP
    $filePath = Join-Path -Path $PSScriptRoot -ChildPath "lastip.log"
    $publicIP | Out-File -FilePath $filePath -Encoding UTF8 -Force
    
    Write-Host "已保存到 $filePath"
    
    # 更新 Cloudflare DNS 记录
	$apiToken = "YOUR_API_TOKEN"
	$zoneId = "YOUR_ZONE_ID"
	$ipAddress = $publicIP
	$recordType = "A"
	$ttl = 1
	$proxied = $false

	# 构建 API 请求 URL
	$apiUrl = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"

	# 构建请求头
	$headers = @{
		"Authorization" = "Bearer $apiToken"
		"Content-Type" = "application/json"
	}

	# 构建请求体
	$body = @{
		"type" = $recordType
		"name" = "$subdomain.$domain"
		"content" = $ipAddress
		"ttl" = $ttl
		"proxied" = $proxied
	} | ConvertTo-Json

	# 发送 POST 请求
	try {
		$response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
		if ($response.success) {
			Write-Host "DNS 记录添加成功。"
		} else {
			Write-Host "DNS 记录添加失败。错误信息: $($response.errors.message)"
		}
	} catch {
		Write-Host "更新 DNS 出错: $($_.Exception.Message)"
	}
}
catch {
    Write-Host "发生错误：$($_.Exception.Message)"
}

#try {
#    $ip = Invoke-RestMethod -Uri "https://ipinfo.io"
#    $publicIP = $ip.ip
#    Write-Host "外网IP地址: $publicIP"
#} catch {
#    Write-Host "无法获取外网IP地址。错误: $($_.Exception.Message)"
#}
