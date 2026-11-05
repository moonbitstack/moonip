// Cross-check helper for the vector generator: reads a JSON request on stdin and
// answers with what Go's net/netip makes of the same inputs. The generator runs
// this next to CPython's ipaddress and keeps only the cases where both agree.
//
//	go run scripts/reference_netip.go < request.json > answer.json
package main

import (
	"encoding/json"
	"net/netip"
	"os"
)

type request struct {
	Addrs     []string `json:"addrs"`
	Prefixes  []string `json:"prefixes"`
	AddrPorts []string `json:"addrports"`
}

type addrAnswer struct {
	OK          bool   `json:"ok"`
	Text        string `json:"text"`
	Expanded    string `json:"expanded"`
	Zoned       bool   `json:"zoned"`
	Bytes       string `json:"bytes"`
	Loopback    bool   `json:"loopback"`
	Multicast   bool   `json:"multicast"`
	LinkLocal   bool   `json:"link_local"`
	Unspecified bool   `json:"unspecified"`
	Private     bool   `json:"private"`
	Global      bool   `json:"global_unicast"`
}

type prefixAnswer struct {
	OK      bool   `json:"ok"`
	Text    string `json:"text"`
	Bits    int    `json:"bits"`
	Masked  string `json:"masked"`
	Netmask string `json:"netmask"`
	First   string `json:"first"`
	Last    string `json:"last"`
}

type addrPortAnswer struct {
	OK   bool   `json:"ok"`
	Text string `json:"text"`
}

type answer struct {
	Addrs     []addrAnswer     `json:"addrs"`
	Prefixes  []prefixAnswer   `json:"prefixes"`
	AddrPorts []addrPortAnswer `json:"addrports"`
}

func hexOf(addr netip.Addr) string {
	raw := addr.AsSlice()
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(raw)*2)
	for _, b := range raw {
		out = append(out, digits[b>>4], digits[b&0x0f])
	}
	return string(out)
}

func describeAddr(s string) addrAnswer {
	addr, err := netip.ParseAddr(s)
	if err != nil {
		return addrAnswer{}
	}
	return addrAnswer{
		OK:          true,
		Text:        addr.String(),
		Expanded:    addr.StringExpanded(),
		Zoned:       addr.Zone() != "",
		Bytes:       hexOf(addr),
		Loopback:    addr.IsLoopback(),
		Multicast:   addr.IsMulticast(),
		LinkLocal:   addr.IsLinkLocalUnicast(),
		Unspecified: addr.IsUnspecified(),
		Private:     addr.IsPrivate(),
		Global:      addr.IsGlobalUnicast(),
	}
}

func describePrefix(s string) prefixAnswer {
	prefix, err := netip.ParsePrefix(s)
	if err != nil {
		// ParsePrefix masks nothing and refuses nothing about host bits, so a
		// failure here means the text itself was wrong.
		return prefixAnswer{}
	}
	masked := prefix.Masked()
	last := lastOf(masked)
	return prefixAnswer{
		OK:      true,
		Text:    prefix.String(),
		Bits:    prefix.Bits(),
		Masked:  masked.String(),
		Netmask: netmaskOf(masked).String(),
		First:   masked.Addr().String(),
		Last:    last.String(),
	}
}

func v4Mask(bits int) uint32 {
	if bits <= 0 {
		return 0
	}
	return ^uint32(0) << (32 - bits)
}

func lastOf(prefix netip.Prefix) netip.Addr {
	addr := prefix.Addr()
	if addr.Is4() {
		v := addr.As4()
		m := v4Mask(prefix.Bits())
		n := uint32(v[0])<<24 | uint32(v[1])<<16 | uint32(v[2])<<8 | uint32(v[3])
		n |= ^m
		return netip.AddrFrom4([4]byte{byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)})
	}
	raw := addr.As16()
	bits := prefix.Bits()
	for i := 0; i < 16; i++ {
		switch byteBits := bits - i*8; {
		case byteBits >= 8:
			// keep every bit of this byte
		case byteBits <= 0:
			raw[i] = 0xff
		default:
			raw[i] |= byte(0xff >> byteBits)
		}
	}
	return netip.AddrFrom16(raw)
}

func netmaskOf(prefix netip.Prefix) netip.Addr {
	if prefix.Addr().Is4() {
		m := v4Mask(prefix.Bits())
		return netip.AddrFrom4([4]byte{byte(m >> 24), byte(m >> 16), byte(m >> 8), byte(m)})
	}
	bits := prefix.Bits()
	raw := [16]byte{}
	for i := 0; i < 16; i++ {
		switch byteBits := bits - i*8; {
		case byteBits >= 8:
			raw[i] = 0xff
		case byteBits > 0:
			raw[i] = byte(0xff << (8 - byteBits))
		}
	}
	return netip.AddrFrom16(raw)
}

func main() {
	var req request
	if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
		panic(err)
	}
	res := answer{
		Addrs:     make([]addrAnswer, 0, len(req.Addrs)),
		Prefixes:  make([]prefixAnswer, 0, len(req.Prefixes)),
		AddrPorts: make([]addrPortAnswer, 0, len(req.AddrPorts)),
	}
	for _, s := range req.Addrs {
		res.Addrs = append(res.Addrs, describeAddr(s))
	}
	for _, s := range req.Prefixes {
		res.Prefixes = append(res.Prefixes, describePrefix(s))
	}
	for _, s := range req.AddrPorts {
		ap, err := netip.ParseAddrPort(s)
		if err != nil {
			res.AddrPorts = append(res.AddrPorts, addrPortAnswer{})
			continue
		}
		res.AddrPorts = append(res.AddrPorts, addrPortAnswer{OK: true, Text: ap.String()})
	}
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(res); err != nil {
		panic(err)
	}
}
