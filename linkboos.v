import os
import flag
import term
import regex
import net.http
import net.urllib

// Example usage:
// The one i used to scan the "Hack-The-Box Horizontall" machine. Worked pretty good for me.
// v run linkboos.v --max-iters 3 http://horizontall.htb

fn main() {	
	println('>> LinkBoos v0.1')

	mut fp := flag.new_flag_parser(os.args)
	max_iters := fp.int('max-iters', `i`, 10, 'How deep should we crawl?')
	crawl_out_of_scope := fp.bool('crawl-out-of-scope', `z`, false, 'Should we crawl out of scope sites?')
	show_out_of_scope := fp.bool('show-out-of-scope', `s`, false, 'Should we show out of scope sites in the results?')

    additional_args := fp.finalize() or {
        eprintln(err)
        println(fp.usage())
        return
    }

	urls := additional_args[1..]

	println('>> Crawling:   ${urls}')
	println('>> Max Iters:  ${max_iters}')
	println('>> OutOfScope: ${crawl_out_of_scope}')

	crawl(urls, max_iters, crawl_out_of_scope, show_out_of_scope, [200, 301])	
}

fn is_in_scope(markers []string, url string) bool {
	for marker in markers {
		if url.contains(marker) {
			return true
		}
	}

	return false
}

fn crawl(in_scope_urls []string, max_iters int, crawl_out_of_scope bool, show_out_of_scope bool, success_status_codes []int) {
	mut urls := []string{}

	for u in in_scope_urls {
		urls << u
	} 

	// TODO: maybe optimize this? support ssh, ftp, ...?
	mut url_regex := regex.regex_opt('(http://)|(https://)|(/)[\-a-zA-Z0-9_/.]+') or { panic(err) }

	// build markers to later mark/skip crawling out-of-scope urls
	mut markers := []string{}

	for u in urls {
		trimmed_url := u.replace('http://', '').replace('https://', '').split('/')[0]
		markers << trimmed_url
	}

	// urls that are crawled in the current iteration
	mut iter_urls := []string{}

	for u in urls {
		iter_urls << u
	}

	// new urls found, these will be crawled next iteration
	mut new_urls := []string{}

	// keep trck of urls we already crawled, no need to crawl them twice
	mut checked_urls := []string{}

	for i in 0 .. max_iters {
		println('\n>> Running Iter: ${i}')

		for u in iter_urls {
			mut base_url := u.split('/')[..3].join('/')
			matches := url_regex.find_all_str(http.get_text(u))

			for m in matches {
				mut t_url := m

				// if http/https is missing, its very likely to be a relative url
				if !t_url.starts_with('h') && !t_url.starts_with('H') {
					if t_url.starts_with('/') {
						// relative to root url
						if base_url.ends_with('/') {
							// strip the trailing slash
							t_url = t_url[1..]
						} else {
							t_url = base_url + t_url
						}
					} else {
						// relative to current url
						t_url = u + t_url
					} 
				}

				// check url integrity
				mut parsed_url := urllib.parse(t_url) or { continue }
				t_url = parsed_url.str()

				// skip url if already crawled
				if t_url in checked_urls {
					continue
				} else {
					checked_urls << t_url					
				}

				resp := http.get(t_url) or { continue }

				mut color := term.white

				if resp.status_code >= 500 {
					color = term.red
				} else if resp.status_code >= 400 {
					color = term.cyan
				} else if resp.status_code >= 300 {
					color = term.yellow
				} else if resp.status_code >= 200 {
					color = term.green
				}

				println('${term.colorize(color, resp.status_code.str())} -> ${t_url}')

				if resp.status_code in success_status_codes {
					if crawl_out_of_scope || is_in_scope(markers, t_url) {
						new_urls << t_url
					}

					if t_url !in urls {
						urls << t_url
					}
				}
			}
		}

		if new_urls.len == 0 {
			println('>> Aborting, no new urls found...')
			break
		} 

		println('\n>> New Urls: ${new_urls}')
		iter_urls = new_urls.clone()
		new_urls = []string{}
	}

	println('\n>> Gathered Links: ')
	urls.sort()

	for u in urls {
		mut color := term.yellow

		if is_in_scope(markers, u) {
			color = term.white
		} else if !show_out_of_scope {
			continue
		} 

		println(term.colorize(color, u))
	}
}