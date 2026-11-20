package core

import (
	"fmt"
	"sort"
	"strings"
	"sync/atomic"

	"github.com/metacubex/mihomo/config"
)

const (
	vpsSmartGroup = "⚡ 智能线路"
	vpsAIGroup    = "🤖 AI 专线"
	vpsProbeURL   = "https://www.gstatic.com/generate_204"
	vpsAIProbeURL = vpsProbeURL + "#vps2vpn-ai"
)

// Set from CoreOptions.SmartLines before each config load.
var vpsSmartEnabled atomic.Bool

var vpsAIDomains = []string{
	"anthropic.com", "claude.ai", "claude.com", "claudeusercontent.com", "clau.de",
	"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "sora.com",
	"gemini.google.com", "notebooklm.google.com", "generativelanguage.googleapis.com", "aistudio.google.com",
	"perplexity.ai", "x.ai", "grok.com",
}

// vpsLineRank: lower is tried first; -1 means not a line to the outside.
func vpsLineRank(p map[string]any) int {
	t := strings.ToLower(fmt.Sprint(p["type"]))
	switch t {
	case "hysteria2", "hysteria", "tuic":
		return 0
	case "vless":
		if _, ok := p["reality-opts"]; ok {
			return 1
		}
		return 2
	case "trojan", "anytls", "vmess", "wireguard":
		return 2
	case "ss", "ssr", "snell", "socks5", "http", "ssh":
		return 3
	case "direct", "reject", "reject-drop", "pass", "dns", "compatible":
		return -1
	}
	return 3
}

func vpsName(p map[string]any) string {
	name, _ := p["name"].(string)
	return name
}

func vpsNameTaken(raw *config.RawConfig, name string) bool {
	if _, exists := raw.ProxyProvider[name]; exists {
		return true
	}
	for _, p := range raw.Proxy {
		if vpsName(p) == name {
			return true
		}
	}
	for _, g := range raw.ProxyGroup {
		if vpsName(g) == name {
			return true
		}
	}
	return false
}

func vpsRoutesAI(rules []string) bool {
	for _, rule := range rules {
		fields := strings.SplitN(rule, ",", 3)
		if len(fields) < 2 {
			continue
		}
		kind := strings.ToUpper(strings.TrimSpace(fields[0]))
		payload := strings.ToLower(strings.TrimSpace(fields[1]))
		switch kind {
		case "RULE-SET", "SUB-RULE", "GEOSITE", "DOMAIN-REGEX", "AND", "OR", "NOT":
			return true
		case "DOMAIN", "DOMAIN-SUFFIX":
			payload = strings.TrimSuffix(payload, ".")
			for _, domain := range vpsAIDomains {
				if payload == domain || strings.HasSuffix(payload, "."+domain) ||
					kind == "DOMAIN-SUFFIX" && strings.HasSuffix(domain, "."+payload) {
					return true
				}
			}
		case "DOMAIN-KEYWORD":
			for _, domain := range vpsAIDomains {
				if payload != "" && strings.Contains(domain, payload) {
					return true
				}
			}
		}
	}
	return false
}

// vps2vpnEnhance adds the smart groups to raw in place. The AI rules go
// after the first userRules rules (the user's own); a negative userRules
// leaves the rules alone.
func vps2vpnEnhance(raw *config.RawConfig, userRules int) {
	if !vpsSmartEnabled.Load() {
		return
	}
	type line struct {
		name   string
		server int
		rank   int
	}
	var lines []line
	servers := map[string]int{}
	for _, p := range raw.Proxy {
		rank := vpsLineRank(p)
		name := vpsName(p)
		if rank < 0 || name == "" {
			continue
		}
		if rank == 1 {
			if fp, _ := p["client-fingerprint"].(string); fp == "" {
				p["client-fingerprint"] = "chrome"
			}
		}
		server, _ := p["server"].(string)
		if server == "" {
			server = "\x00" + name
		}
		order, exists := servers[server]
		if !exists {
			order = len(servers)
			servers[server] = order
		}
		lines = append(lines, line{name: name, server: order, rank: rank})
	}
	// One line has nothing to fall back to; a second protocol is what makes this useful.
	if len(lines) < 2 || vpsNameTaken(raw, vpsSmartGroup) {
		return
	}
	sort.SliceStable(lines, func(i, j int) bool {
		if lines[i].server != lines[j].server {
			return lines[i].server < lines[j].server
		}
		return lines[i].rank < lines[j].rank
	})
	smart := make([]string, len(lines))
	for i, l := range lines {
		smart[i] = l.name
	}
	raw.ProxyGroup = append(raw.ProxyGroup, map[string]any{
		"name":             vpsSmartGroup,
		"type":             "fallback",
		"proxies":          smart,
		"url":              vpsProbeURL,
		"interval":         60,
		"timeout":          2500,
		"max-failed-times": 2,
		"lazy":             false,
	})
	// Offer it first in the main selector.
	for _, g := range raw.ProxyGroup {
		if strings.ToLower(fmt.Sprint(g["type"])) != "select" {
			continue
		}
		var members []any
		switch values := g["proxies"].(type) {
		case nil:
		case []any:
			members = values
		case []string:
			for _, name := range values {
				members = append(members, name)
			}
		default:
			continue
		}
		g["proxies"] = append([]any{vpsSmartGroup}, members...)
		break
	}

	if userRules < 0 || vpsRoutesAI(raw.Rule) || vpsNameTaken(raw, vpsAIGroup) {
		return
	}
	aiNames := append([]string(nil), smart...)
	raw.ProxyGroup = append(raw.ProxyGroup, map[string]any{
		"name":               vpsAIGroup,
		"type":               "fallback",
		"proxies":            aiNames,
		"url":                vpsAIProbeURL,
		"interval":           120,
		"timeout":            4000,
		"max-failed-times":   3,
		"failure-threshold":  3,
		"recovery-threshold": 3,
		"lazy":               false,
	})
	userRules = min(userRules, len(raw.Rule))
	rules := make([]string, 0, len(vpsAIDomains)+len(raw.Rule))
	rules = append(rules, raw.Rule[:userRules]...)
	for _, d := range vpsAIDomains {
		rules = append(rules, "DOMAIN-SUFFIX,"+d+","+vpsAIGroup)
	}
	raw.Rule = append(rules, raw.Rule[userRules:]...)
}
